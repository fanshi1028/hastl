{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Api.User where

import Control.Monad.Except (MonadIO (liftIO))
import Control.Monad.Logger (logDebugNS, logErrorNS)
import Database.Persist.Postgresql (
  Entity (..),
  PersistStoreRead (get),
  getEntity,
  insert,
  selectFirst,
  selectList,
  (==.),
 )
import Servant (
  Capture,
  Get,
  HasServer (ServerT),
  JSON,
  Post,
  Proxy (..),
  ReqBody,
  ServerError (errBody, errHTTPCode, errHeaders),
  addHeader,
  err404,
  err500,
  throwError,
  type (:<|>) (..),
  type (:>),
 )

import Api.Templates.Helpers.Htmx (hxTarget_)
import Api.Templates.User.User (renderUser, renderUsersComponent)
import Config (AppT (..))
import Data.Aeson (FromJSON)
import Data.Text (Text, pack)
import Data.Time (getCurrentTime)
import GHC.Generics (Generic)
import Lucid (Html, ToHtml (toHtml), class_, div_, id_, p_, renderBS)
import Models (User (User), runDb, tryRunDb)
import Models qualified as Md
import Servant.API.ContentTypes.Lucid (HTML)

data CreateUserPayload = CreateUserPayload
  { name :: Text
  , email :: Text
  }
  deriving (Generic)

instance FromJSON CreateUserPayload

type UserAPI =
  "users" :> Get '[HTML] (Html ())
    :<|> "users" :> Capture "name" Data.Text.Text :> Get '[JSON] (Entity User)
    :<|> "users" :> ReqBody '[JSON] CreateUserPayload :> Post '[HTML] (Html ())

userApi :: Proxy UserAPI
userApi = Proxy

-- | The server that runs the UserAPI
userServer :: (MonadIO m) => ServerT UserAPI (AppT m)
userServer = allUsers :<|> singleUser :<|> createUser

-- | Returns all users in the database.
allUsers :: (MonadIO m) => AppT m (Html ())
allUsers = do
  logDebugNS "web" "allUsers"
  users :: [Entity User] <- runDb (selectList [] [])
  return $ renderUsersComponent users

-- | Returns a user by name or throws a 404 error.
singleUser :: (MonadIO m) => Data.Text.Text -> AppT m (Entity User)
singleUser str = do
  logDebugNS "web" "singleUser"
  maybeUser <- runDb (selectFirst [Md.UserName ==. str] [])
  case maybeUser of
    Nothing ->
      throwError err404
    Just person ->
      return person

-- | Creates a user in the database.
createUser :: (MonadIO m) => CreateUserPayload -> AppT m (Html ())
createUser u = do
  logDebugNS "web" "creating a user"
  time <- liftIO getCurrentTime
  result <- tryRunDb (insert (User (name u) (email u) time))
  case result of
    Left exception -> do
      logErrorNS "web" (Data.Text.pack (show exception))
      throwError $
        err500
          { errHeaders =
              [ ("HX-Retarget", "#form-errors")
              , ("HX-Reswap", "outerHTML")
              , ("Access-Control-Allow-Origin", "*") -- Enable CORS
              ]
          , errBody =
              renderBS $
                div_
                  [ id_ "form-errors"
                  , class_ "max-w-2lg mx-auto mt-2 flex inline-flex justify-between bg-red-100 border border-red-400 text-red-700 my-2 rounded "
                  ]
                  (toHtml (show exception))
          , errHTTPCode = 200 -- This is a hack to make sure htmx displays our error
          }
    Right key -> do
      logDebugNS "web" "User created"
      maybeUser <- runDb (getEntity key)
      case maybeUser of
        Nothing -> do
          logErrorNS
            "web"
            "Failed to create user"
          throwError err500
        Just user ->
          return $ renderUser user
