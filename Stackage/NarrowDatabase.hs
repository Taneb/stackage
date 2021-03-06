module Stackage.NarrowDatabase where

import           Control.Monad.Trans.Writer
import qualified Data.Map                   as Map
import qualified Data.Set                   as Set
import           Prelude                    hiding (pi)
import           Stackage.Types
import           Stackage.Util

-- | Narrow down the database to only the specified packages and all of
-- their dependencies.
narrowPackageDB :: SelectSettings
                -> Set PackageName -- ^ core packages to be excluded from installation
                -> PackageDB
                -> Set (PackageName, Maintainer)
                -> IO (Map PackageName BuildInfo, Set String)
narrowPackageDB settings core (PackageDB pdb) packageSet =
    runWriterT $ loop Map.empty $ Set.map (\(name, maintainer) -> ([], name, maintainer)) packageSet
  where
    loop result toProcess =
        case Set.minView toProcess of
            Nothing -> return result
            Just ((users, p, maintainer), toProcess') ->
                case Map.lookup p pdb of
                    Nothing
                        | p `Set.member` core -> loop result toProcess'
                        | null users -> error $ "Unknown package: " ++ show p
                        | otherwise -> loop result toProcess'
                    Just pi -> do
                        let users' = p:users
                            result' = Map.insert p BuildInfo
                                { biVersion    = piVersion pi
                                , biUsers      = users
                                , biMaintainer = maintainer
                                , biDeps       = piDeps pi
                                , biGithubUser = piGithubUser pi
                                , biHasTests   = piHasTests pi
                                } result
                        case piGPD pi of
                            Nothing -> return ()
                            Just gpd ->
                                case allowedPackage settings gpd of
                                    Left msg -> tell $ Set.singleton $ concat
                                        [ packageVersionString (p, piVersion pi)
                                        , ": "
                                        , msg
                                        ]
                                    Right () -> return ()
                        loop result' $ Set.foldl' (addDep users' result' maintainer) toProcess' $ Map.keysSet $ piDeps pi
    addDep users result maintainer toProcess p =
        case Map.lookup p result of
            Nothing -> Set.insert (users, p, maintainer) toProcess
            Just{} -> toProcess
