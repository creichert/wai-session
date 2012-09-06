module Network.Wai.Session.Map (mapStore, mapStore_) where

import Control.Monad
import Data.StateVar
import Data.String (fromString)
import Data.ByteString (ByteString)
import Control.Monad.IO.Class (liftIO, MonadIO)
import Data.IORef
import Data.Unique
import Data.Ratio
import Data.Time.Clock.POSIX
import Network.Wai.Session (Session)

import Data.Map (Map)
import qualified Data.Map as Map

mapStore :: (Ord k, MonadIO m) =>
	IO ByteString ->
	Maybe ByteString ->
	IO (Session m k v, ByteString)
mapStore gen key =
	newThreadSafeStateVar Map.empty >>= mapStore' gen key
	where
	mapStore' _ (Just k) ssv = do
		m <- get ssv
		case Map.lookup k m of
			Just sv -> return (sessionFromMapStateVar sv, k)
			-- Could not find key, so it's as if we were not sent one
			Nothing -> mapStore' (return k) Nothing ssv
	mapStore' genNewKey Nothing ssv = do
		newKey <- genNewKey
		sv <- newThreadSafeStateVar Map.empty
		ssv $~ Map.insert newKey sv
		return (sessionFromMapStateVar sv, newKey)

mapStore_ :: (Ord k, MonadIO m) =>
	Maybe ByteString ->
	IO (Session m k v, ByteString)
mapStore_ = mapStore (do
		u <- fmap (toInteger . hashUnique) newUnique
		time <- fmap toRational getPOSIXTime
		return $ fromString $ show (numerator time * denominator time * u)
	)

newThreadSafeStateVar :: a -> IO (StateVar a)
newThreadSafeStateVar a = do
	ref <- newIORef a
	return $ makeStateVar
		(atomicModifyIORef ref (\x -> (x,x)))
		(\x -> atomicModifyIORef ref (const (x,())))

sessionFromMapStateVar :: (HasGetter sv, HasSetter sv, Ord k, MonadIO m) =>
	sv (Map k v) ->
	Session m k v
sessionFromMapStateVar sv = (
		(\k -> Map.lookup k `liftM` liftIO (get sv)),
		(\k v -> liftIO (sv $~ Map.insert k v))
	)
