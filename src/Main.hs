{-# LANGUAGE OverloadedStrings #-}

module Main
  ( main
  )
where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forever, join)
import Reactive.Banana
import Reactive.Banana.Frameworks

import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as Text
import qualified Data.Text.IO as Text
import qualified Data.Text as Text
import qualified Network.Socket as Network hiding (recv)
import qualified Network.Socket.ByteString as Network

-- | Server logic.
server :: Network.Socket -> MomentIO ()
server serverSock = do
  clientSock         <- addSockEvent serverSock

  messageReceived    <- execute $ fmap receiveMessage clientSock

  -- Interleave all received messages from all clients.
  anyMessageReceived <- accumE never (unionWith const <$> messageReceived) >>= switchE

  reactimate $ fmap go anyMessageReceived
  where go msg = Text.putStrLn ("Received " <> msg)

-- | An event for when a client connects. The payload of the event is the
-- Socket conntected to the new client.
addSockEvent :: Network.Socket -> MomentIO (Event Network.Socket)
addSockEvent serverSock = do
  -- ah is a type of AddHandler, for registering event handlers.
  -- fire is typical a function takes an event value and perform a IO computation.
  (ah, fire) <- liftIO newAddHandler

  -- Fork a new thread that constantly tries to accept new connections.
  -- Whenever 'accept' succeeds, pass the 'Socket' to fire
  (liftIO . forkIO) $ do
    (sock, addr) <- Network.accept serverSock
    fire sock

  -- Convert the 'AddHandler' into an 'Event'
  fromAddHandler ah

receiveMessage :: Network.Socket -> MomentIO (Event Text.Text)
receiveMessage sock = do
  (ah, fire) <- liftIO newAddHandler
  liftIO $ forkIO $ go fire
  fromAddHandler ah

 where
  go fire = do
    bytes <- Network.recv sock 1024
    if BS.null bytes then return () else fire (Text.decodeUtf8 bytes) >> go fire

main :: IO ()
main = do
  let
    hints = Network.defaultHints
      { Network.addrFlags      = [Network.AI_PASSIVE]
      , Network.addrSocketType = Network.Stream
      }
  -- Address infor return a list of addresses, pick the first one here.
  addr : _   <- Network.getAddrInfo (Just hints) Nothing (Just "3000")

  serverSock <- Network.socket
    (Network.addrFamily addr)
    (Network.addrSocketType addr)
    (Network.addrProtocol addr)

  Network.bind serverSock (Network.addrAddress addr)
  Network.listen serverSock 10

  -- Compile and actuate the frp graph.
  compile (server serverSock) >>= actuate

  forever (threadDelay maxBound)
