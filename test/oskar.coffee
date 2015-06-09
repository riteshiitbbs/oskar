
# Setup the tests
###################################################################
should = require 'should'
sinon = require 'sinon'
whenLib = require 'when'
{EventEmitter} = require 'events'

# Client = require '../src/client'
Oskar = require '../src/oskar'
MongoClient = require '../src/modules/mongoClient'
SlackClient = require '../src/modules/slackClient'

###################################################################
# Helper
###################################################################

describe 'oskar', ->

  mongo = new MongoClient()
  slack = new SlackClient()

  # slack stubs, because these methods are unit tested elsewhere
  getUserStub = sinon.stub slack, 'getUser'
  getUserIdsStub = sinon.stub slack, 'getUserIds'
  isUserCommentAllowedStub = sinon.stub slack, 'isUserCommentAllowed'
  disallowUserCommentStub = sinon.stub slack, 'disallowUserComment'
  postMessageStub = sinon.stub slack, 'postMessage'

  # mongo stubs
  userExistsStub = sinon.stub mongo, 'userExists'
  saveUserStub = sinon.stub mongo, 'saveUser'
  getLatestUserTimestampStub = sinon.stub mongo, 'getLatestUserTimestampForProperty'
  saveUserStatusStub = sinon.stub mongo, 'saveUserStatus'
  getLatestUserFeedbackStub = sinon.stub mongo, 'getLatestUserFeedback'
  getAllUserFeedback = sinon.stub mongo, 'getAllUserFeedback'
  saveUserFeedbackStub = sinon.stub mongo, 'saveUserFeedback'
  saveUserFeedbackMessageStub = sinon.stub mongo, 'saveUserFeedbackMessage'

  # stub promises
  userExistsStub.returns(whenLib false)
  saveUserStub.returns(whenLib false)
  getLatestUserTimestampStub.returns(whenLib false)

  # Oskar spy
  presenceHandlerSpy = sinon.spy Oskar.prototype, 'presenceHandler'

  oskar = new Oskar(mongo, slack)
  composeMessageStub = null
  doOnboardingStub = null

  # timestamps
  today = Date.now()
  yesterday = today - (3600 * 1000 * 21)

  ###################################################################
  # HelperMethods
  ###################################################################

  describe 'HelperMethods', ->

    it 'should post a message to slack', ->

      userId = 'user1'
      messageType = 'alreadySubmitted'

      oskar.composeMessage userId, messageType

      postMessageStub.called.should.be.equal true
      postMessageStub.args[0][0].should.be.equal userId

    it 'should send presence events when checkForUserStatus is called', (done) ->

      targetUserIds = [2, 3]
      getUserIdsStub.returns(targetUserIds)

      oskar.checkForUserStatus(slack)

      setTimeout ->
        presenceHandlerSpy.callCount.should.be.equal 2
        done()
      , 100

  ###################################################################
  # Presence handler
  ###################################################################

  describe 'presenceHandler', ->

    before ->
      presenceHandlerSpy.restore()
      disallowUserCommentStub.reset()

    it 'should save a non-existing user in mongo', (done) ->
      data =
        userId: 'user1'

      oskar.presenceHandler data
      setTimeout ->
        saveUserStub.called.should.be.equal true
        done()
      , 100

    it 'should return false if user is disabled', ->
      data =
        userId: '***REMOVED***'

      getUserStub.returns(null)

      res = oskar.presenceHandler data
      res.should.be.equal(false)

    it 'should disallow user comments when triggered', ->
      userObj =
        userId: '***REMOVED***'

      data =
        userId: '***REMOVED***'
        status: 'triggered'

      getUserStub.returns(data)
      oskar.presenceHandler data
      disallowUserCommentStub.called.should.be.equal true

    after ->
      disallowUserCommentStub.reset()


    ###################################################################
    # Presence handler > requestFeedback
    ###################################################################

    describe 'requestFeedback', ->

      before ->
        composeMessageStub = sinon.stub oskar, 'composeMessage'
        doOnboardingStub = sinon.stub oskar, 'doOnboarding'

      beforeEach ->
        composeMessageStub.reset()

      data =
        userId: 'user1'
        status: 'active'

      it 'should request feedback from an existing user if timestamp expired', (done) ->

        userObj =
          id: 'user1'
          presence: 'active'

        getUserStub.returns userObj

        oskar.presenceHandler data
        getLatestUserTimestampStub.returns(whenLib yesterday)

        setTimeout ->
          composeMessageStub.called.should.be.equal true
          composeMessageStub.args[0][0].should.be.equal 'user1'
          composeMessageStub.args[0][1].should.be.equal 'requestFeedback'
          done()
        , 100

      it 'should not request feedback from an existing user if timestamp not expired', (done) ->

        oskar.presenceHandler data
        getLatestUserTimestampStub.returns(whenLib today)

        setTimeout ->
          composeMessageStub.called.should.be.equal false
          done()
        , 100

      it 'should not request feedback from an existing user if status is not active or triggered', (done) ->

        data.status = 'away'
        getLatestUserTimestampStub.returns(whenLib yesterday)

        oskar.presenceHandler data

        setTimeout ->
          composeMessageStub.called.should.be.equal false
          done()
        , 100

      it 'should not request user feedback if user isn\'t active', (done) ->

        userObj =
          userId: 'user2'
          presence: 'away'

        getUserStub.returns userObj

        data.status = 'triggered'
        oskar.presenceHandler data
        getLatestUserTimestampStub.returns(whenLib yesterday)

        setTimeout ->
          composeMessageStub.called.should.be.equal false
          done()
        , 100

      it 'should trigger the onboarding process when feedback is null', (done) ->

        userObj =
          userId: 'user3'
          presence: 'active'

        getUserStub.returns userObj
        getLatestUserTimestampStub.returns(whenLib null)
        oskar.requestUserFeedback 'user3', 'active'

        setTimeout =>
          doOnboardingStub.called.should.be.equal true
          done()
        , 100


  ###################################################################
  # Message handler
  ###################################################################

  describe 'messageHandler', ->

    beforeEach ->
      composeMessageStub.reset()
      saveUserFeedbackStub.reset()

    it 'should reveal status for a user', (done) ->

      message =
        text: 'How is <@USER2>?'
        user: 'user1'

      targetUserObj =
        id: 'USER2',
        name: 'matt'
        user:
          profile:
            first_name: 'User 2'

      res =
        status: 8
        message: 'feeling great'

      getUserStub.returns(targetUserObj)
      getLatestUserFeedbackStub.returns(whenLib res)

      oskar.messageHandler message
      setTimeout ->
        composeMessageStub.args[0][0].should.be.equal('user1')
        composeMessageStub.args[0][1].should.be.equal('revealUserStatus')
        composeMessageStub.args[0][2].status.should.be.equal(res.status)
        composeMessageStub.args[0][2].message.should.be.equal(res.message)
        composeMessageStub.args[0][2].user.should.be.equal(targetUserObj)
        done()
      , 100

    it 'should reveal status for the channel', (done) ->

      message =
        text: 'How is <@channel>?'
        user: 'user1'

      res =
        0:
          id: 'user2'
          feedback:
            status: 4
            message: 'bad mood'
        1:
          id: 'user3'
          feedback:
            status: 2
            message: 'physically down'

      targetUserIds = [2, 3]

      getUserIdsStub.returns(targetUserIds)
      getAllUserFeedback.returns(whenLib res)

      oskar.messageHandler message
      setTimeout ->
        composeMessageStub.args[0][1].should.be.equal('revealChannelStatus')
        composeMessageStub.args[0][2].should.be.equal(res)
        done()
      , 100

    it 'should save user feedback message', (done) ->

      message =
        text: '5'
        user: 'user1'

      getLatestUserTimestampStub.returns(whenLib yesterday)

      oskar.messageHandler message

      setTimeout ->
        saveUserFeedbackStub.called.should.be.equal true
        composeMessageStub.args[0][1].should.be.equal 'feedbackReceived'
        done()
      , 100

    it 'should not allow feedback if already submitted', (done) ->

      message =
        text: '7'
        user: 'user1'

      getLatestUserTimestampStub.returns(whenLib today)

      oskar.messageHandler message

      setTimeout ->
        saveUserFeedbackStub.called.should.be.equal false
        composeMessageStub.called.should.be.equal true
        composeMessageStub.args[0][0].should.be.equal message.user
        composeMessageStub.args[0][1].should.be.equal 'alreadySubmitted'
        done()
      , 100

    it 'should not allow invalid feedback', (done) ->

      message =
        text: 'something'
        user: 'user1'

      getLatestUserTimestampStub.returns(whenLib yesterday)

      oskar.messageHandler message

      setTimeout ->
        composeMessageStub.called.should.be.equal true
        composeMessageStub.args[0][0].should.be.equal message.user
        composeMessageStub.args[0][1].should.be.equal 'invalidInput'
        done()
      , 100

    it 'should ask user for feedback message if feedback low', (done) ->

      message =
        text: '2'
        user: 'user1'

      getLatestUserTimestampStub.returns(whenLib yesterday)

      oskar.messageHandler message

      setTimeout ->
        composeMessageStub.called.should.be.equal true
        composeMessageStub.args[0][0].should.be.equal message.user
        composeMessageStub.args[0][1].should.be.equal 'lowFeedback'
        done()
      , 100

    it 'should thank the user for feedback message if feedback allowed, save feedback to mongo and disallow comment', (done) ->

      message =
        text: 'not feeling so well'
        user: 'user1'

      isUserCommentAllowedStub.returns(whenLib true)

      oskar.messageHandler message

      setTimeout ->
        composeMessageStub.called.should.be.equal true
        composeMessageStub.args[0][0].should.be.equal message.user
        composeMessageStub.args[0][1].should.be.equal 'feedbackMessageReceived'
        saveUserFeedbackMessageStub.called.should.be.equal true
        disallowUserCommentStub.called.should.be.equal true
        done()
      , 100

    it 'should trigger a presence event for each user', ->

      spy = sinon.spy()

      slack.on 'presence', spy
      getUserIdsStub.returns ['testuser1', 'testuser2']

      oskar.checkForUserStatus(slack)

      spy.callCount.should.be.equal 2
      spy.firstCall.args[0].userId.should.be.equal 'testuser1'
      spy.firstCall.args[0].status.should.be.equal 'triggered'
      spy.secondCall.args[0].userId.should.be.equal 'testuser2'
      spy.secondCall.args[0].status.should.be.equal 'triggered'