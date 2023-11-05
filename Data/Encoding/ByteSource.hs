{-# LANGUAGE FlexibleInstances,FlexibleContexts,MultiParamTypeClasses,CPP #-}
module Data.Encoding.ByteSource where

import Data.Encoding.Exception

import Data.Bits
import Data.Binary.Get
import Data.Char
import Data.Maybe
import Data.Word
import Control.Applicative as A
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State (StateT (..), get, gets, put)
import Control.Monad.Identity (Identity)
import Control.Monad.Reader (ReaderT, ask)
import Control.Exception.Extensible
import Control.Throws
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import System.IO

class (Monad m,Throws DecodingException m) => ByteSource m where
    sourceEmpty :: m Bool
    fetchWord8 :: m Word8
    -- 'fetchAhead act' should return the same thing 'act' does, but should
    -- only consume input if 'act' returns a 'Just' value
    fetchAhead :: m (Maybe a) -> m (Maybe a)
    fetchWord16be :: m Word16
    fetchWord16be = do
      w1 <- fetchWord8
      w2 <- fetchWord8
      return $ ((fromIntegral w1) `shiftL` 8)
                 .|. (fromIntegral w2)
    fetchWord16le :: m Word16
    fetchWord16le = do
      w1 <- fetchWord8
      w2 <- fetchWord8
      return $ ((fromIntegral w2) `shiftL` 8)
                 .|. (fromIntegral w1)
    fetchWord32be :: m Word32
    fetchWord32be = do
      w1 <- fetchWord8
      w2 <- fetchWord8
      w3 <- fetchWord8
      w4 <- fetchWord8
      return $ ((fromIntegral w1) `shiftL` 24)
                 .|. ((fromIntegral w2) `shiftL` 16)
                 .|. ((fromIntegral w3) `shiftL`  8)
                 .|. (fromIntegral w4)
    fetchWord32le :: m Word32
    fetchWord32le = do
      w1 <- fetchWord8
      w2 <- fetchWord8
      w3 <- fetchWord8
      w4 <- fetchWord8
      return $ ((fromIntegral w4) `shiftL` 24)
                 .|. ((fromIntegral w3) `shiftL` 16)
                 .|. ((fromIntegral w2) `shiftL`  8)
                 .|. (fromIntegral w1)
    fetchWord64be :: m Word64
    fetchWord64be = do
      w1 <- fetchWord8
      w2 <- fetchWord8
      w3 <- fetchWord8
      w4 <- fetchWord8
      w5 <- fetchWord8
      w6 <- fetchWord8
      w7 <- fetchWord8
      w8 <- fetchWord8
      return $ ((fromIntegral w1) `shiftL` 56)
                 .|. ((fromIntegral w2) `shiftL` 48)
                 .|. ((fromIntegral w3) `shiftL` 40)
                 .|. ((fromIntegral w4) `shiftL` 32)
                 .|. ((fromIntegral w5) `shiftL` 24)
                 .|. ((fromIntegral w6) `shiftL` 16)
                 .|. ((fromIntegral w7) `shiftL`  8)
                 .|. (fromIntegral w8)
    fetchWord64le :: m Word64
    fetchWord64le = do
      w1 <- fetchWord8
      w2 <- fetchWord8
      w3 <- fetchWord8
      w4 <- fetchWord8
      w5 <- fetchWord8
      w6 <- fetchWord8
      w7 <- fetchWord8
      w8 <- fetchWord8
      return $ ((fromIntegral w8) `shiftL` 56)
                 .|. ((fromIntegral w7) `shiftL` 48)
                 .|. ((fromIntegral w6) `shiftL` 40)
                 .|. ((fromIntegral w5) `shiftL` 32)
                 .|. ((fromIntegral w4) `shiftL` 24)
                 .|. ((fromIntegral w3) `shiftL` 16)
                 .|. ((fromIntegral w2) `shiftL`  8)
                 .|. (fromIntegral w1)

instance Throws DecodingException Get where
    throwException = throw

instance ByteSource Get where
    sourceEmpty = isEmpty
    fetchWord8 = getWord8
#if MIN_VERSION_binary(0,6,0)
    fetchAhead act = (do
        res <- act
        case res of
            Nothing -> A.empty
            Just a  -> return res
        ) <|> return Nothing
#else
    fetchAhead act = do
        res <- lookAhead act
        case res of
            Nothing -> return Nothing
            Just a  -> act
#endif
    fetchWord16be = getWord16be
    fetchWord16le = getWord16le
    fetchWord32be = getWord32be
    fetchWord32le = getWord32le
    fetchWord64be = getWord64be
    fetchWord64le = getWord64le

fetchAheadState act = do
    chs <- get
    res <- act
    when (isNothing res) (put chs)
    return res

instance ByteSource (StateT [Char] Identity) where
    sourceEmpty = gets null
    fetchWord8 = do
      chs <- get
      case chs of
        [] -> throwException UnexpectedEnd
        c:cs -> do
          put cs
          return (fromIntegral $ ord c)
    fetchAhead = fetchAheadState

#if MIN_VERSION_base(4,3,0)
#else
instance Monad (Either DecodingException) where
    return = Right
    (Left err) >>= g = Left err
    (Right x) >>= g = g x
#endif

instance ByteSource (StateT [Char] (Either DecodingException)) where
    sourceEmpty = gets null
    fetchWord8 = do
      chs <- get
      case chs of
        [] -> throwException UnexpectedEnd
        c:cs -> do
          put cs
          return (fromIntegral $ ord c)
    fetchAhead = fetchAheadState

instance (Monad m,Throws DecodingException m) => ByteSource (StateT BS.ByteString m) where
    sourceEmpty = gets BS.null
    fetchWord8 = StateT (\str -> case BS.uncons str of
                                  Nothing -> throwException UnexpectedEnd
                                  Just (c,cs) -> return (c,cs))
    fetchAhead = fetchAheadState

instance ByteSource (StateT LBS.ByteString (Either DecodingException)) where
    sourceEmpty = gets LBS.null
    fetchWord8 = StateT (\str -> case LBS.uncons str of
                                  Nothing -> Left UnexpectedEnd
                                  Just ns -> Right ns)
    fetchAhead = fetchAheadState

instance ByteSource (ReaderT Handle IO) where
    sourceEmpty = do
      h <- ask
      liftIO (hIsEOF h)
    fetchWord8 = do
      h <- ask
      liftIO $ do
        ch <- hGetChar h
        return (fromIntegral $ ord ch)
    fetchAhead act = do
      h <- ask
      pos <- liftIO $ hGetPosn h
      res <- act
      when (isNothing res) (liftIO $ hSetPosn pos)
      return res
