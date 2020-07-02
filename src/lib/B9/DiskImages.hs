-- | Data types that describe all B9 relevant elements of virtual machine disk
-- images.
module B9.DiskImages where

import B9.QCUtil
import Control.Parallel.Strategies
import Data.Binary
import Data.Data
import Data.Hashable
import Data.Map (Map)
import Data.Maybe
import Data.Semigroup as Sem
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)
import System.FilePath
import Test.Hspec (Spec, describe, it)
import Test.QuickCheck
import qualified Text.PrettyPrint.Boxes as Boxes
import Text.Printf

-- * Data types for disk image description, e.g. 'ImageTarget',
-- 'ImageDestination', 'Image', 'MountPoint', 'SharedImage'

-- | Build target for disk images; the destination, format and size of the image
-- to generate, as well as how to create or obtain the image before a
-- 'B9.Vm.VmScript' is executed with the image mounted at a 'MountPoint'.
data ImageTarget
  = ImageTarget
      ImageDestination
      ImageSource
      MountPoint
  deriving (Read, Show, Typeable, Data, Eq, Generic)

instance Hashable ImageTarget

instance Binary ImageTarget

instance NFData ImageTarget

-- | A mount point or 'NotMounted'
data MountPoint = MountPoint FilePath | NotMounted
  deriving (Show, Read, Typeable, Data, Eq, Generic)

instance Hashable MountPoint

instance Binary MountPoint

instance NFData MountPoint

-- | The destination of an image.
data ImageDestination
  = -- | Create the image and some meta data so that other
    -- builds can use them as 'ImageSource's via 'From'.
    Share String ImageType ImageResize
  | -- | __DEPRECATED__ Export a raw image that can directly
    -- be booted.
    LiveInstallerImage String FilePath ImageResize
  | -- | Write an image file to the path in the first
    -- argument., possible resizing it,
    LocalFile Image ImageResize
  | -- | Do not export the image. Usefule if the main
    -- objective of the b9 build is not an image file, but
    -- rather some artifact produced by executing by a
    -- containerize build.
    Transient
  deriving (Read, Show, Typeable, Data, Eq, Generic)

instance Hashable ImageDestination

instance Binary ImageDestination

instance NFData ImageDestination

-- | Specification of how the image to build is obtained.
data ImageSource
  = -- | Create an empty image file having a file system label
    -- (first parameter), a file system type (e.g. 'Ext4') and an
    -- 'ImageSize'
    EmptyImage String FileSystem ImageType ImageSize
  | -- | __DEPRECATED__
    CopyOnWrite Image
  | -- | Clone an existing image file; if the image file contains
    -- partitions, select the partition to use, b9 will extract
    -- that partition by reading the offset of the partition from
    -- the partition table and extract it using @dd@.
    SourceImage Image Partition ImageResize
  | -- | Use an image previously shared by via 'Share'.
    From String ImageResize
  deriving (Show, Read, Typeable, Data, Eq, Generic)

instance Hashable ImageSource

instance Binary ImageSource

instance NFData ImageSource

-- | The partition to extract.
data Partition
  = -- | There is no partition table on the image
    NoPT
  | -- | Extract partition @n@ @n@ must be in @0..3@
    Partition Int
  deriving (Eq, Show, Read, Typeable, Data, Generic)

instance Hashable Partition

instance Binary Partition

instance NFData Partition

-- | A vm disk image file consisting of a path to the image file, and the type
-- and file system.
data Image = Image FilePath ImageType FileSystem
  deriving (Eq, Show, Read, Typeable, Data, Generic)

instance Hashable Image

instance Binary Image

instance NFData Image

-- | An image type defines the actual /file format/ of a file containing file
-- systems. These are like /virtual harddrives/
data ImageType = Raw | QCow2 | Vmdk
  deriving (Eq, Read, Typeable, Data, Show, Generic)

instance Hashable ImageType

instance Binary ImageType

instance NFData ImageType

-- | The file systems that b9 can use and convert.
data FileSystem = NoFileSystem | Ext4 | Ext4_64 | ISO9660 | VFAT
  deriving (Eq, Show, Read, Typeable, Data, Generic)

instance Hashable FileSystem

instance Binary FileSystem

instance NFData FileSystem

-- | A data type for image file or file system size; instead of passing 'Int's
-- around this also captures a size unit so that the 'Int' can be kept small
data ImageSize = ImageSize Int SizeUnit
  deriving (Eq, Show, Read, Typeable, Data, Generic)

instance Hashable ImageSize

instance Binary ImageSize

instance NFData ImageSize

-- | Convert a size in bytes to an 'ImageSize'
bytesToKiloBytes :: Int -> ImageSize
bytesToKiloBytes x =
  let kbRoundedDown = x `div` 1024
      rest = x `mod` 1024
      kbRoundedUp = if rest > 0 then kbRoundedDown + 1 else kbRoundedDown
   in ImageSize kbRoundedUp KB

-- | Convert an 'ImageSize' to kibi bytes.
imageSizeToKiB :: ImageSize -> Int
imageSizeToKiB (ImageSize size unit) =
  size * sizeUnitKiB unit

-- | Convert a 'SizeUnit' to the number of kibi bytes one element represents.
sizeUnitKiB :: SizeUnit -> Int
sizeUnitKiB GB = 1024 * sizeUnitKiB MB
sizeUnitKiB MB = 1024 * sizeUnitKiB KB
sizeUnitKiB KB = 1

-- | Choose the greatest unit possible to exactly represent an 'ImageSize'.
normalizeSize :: ImageSize -> ImageSize
normalizeSize i@(ImageSize _ GB) = i
normalizeSize i@(ImageSize size unit)
  | size `mod` 1024 == 0 =
    normalizeSize (ImageSize (size `div` 1024) (succ unit))
  | otherwise = i

-- | Return the sum of two @'ImageSize's@.
addImageSize :: ImageSize -> ImageSize -> ImageSize
-- of course we could get more fancy, but is it really needed? The file size will always be bytes ...
addImageSize (ImageSize value unit) (ImageSize value' unit') =
  normalizeSize
    (ImageSize (value * sizeUnitKiB unit + value' * sizeUnitKiB unit') KB)

-- | Enumeration of size multipliers. The exact semantics may vary depending on
-- what external tools look at these. E.g. the size unit is convert to a size
-- parameter of the @qemu-img@ command line tool.
data SizeUnit = KB | MB | GB
  deriving (Eq, Show, Read, Ord, Enum, Bounded, Typeable, Data, Generic)

instance Hashable SizeUnit

instance Binary SizeUnit

instance NFData SizeUnit

-- | How to resize an image file.
data ImageResize
  = -- | Resize the image __but not the file system__. Note that
    -- a file system contained in the image file might be
    -- corrupted by this operation. To not only resize the image
    -- file but also the fil system contained in it, use
    -- 'Resize'.
    ResizeImage ImageSize
  | -- | Resize an image and the contained file system.
    Resize ImageSize
  | -- | Shrink to minimum size needed and increase by the amount given.
    ShrinkToMinimumAndIncrease ImageSize
  | -- | Resize an image and the contained file system to the
    -- smallest size to fit the contents of the file system.
    ShrinkToMinimum
  | -- | Do not change the image size.
    KeepSize
  deriving (Eq, Show, Read, Typeable, Data, Generic)

instance Hashable ImageResize

instance Binary ImageResize

instance NFData ImageResize

-- | A type alias that indicates that something of type @a@ is mount at a
-- 'MountPoint'
type Mounted a = (a, MountPoint)

-- * Shared Images

-- | 'SharedImage' holds all data necessary to describe an __instance__ of a shared
--    image identified by a 'SharedImageName'. Shared images are stored in
--    'B9.Repository's.
data SharedImage
  = SharedImage
      SharedImageName
      SharedImageDate
      SharedImageBuildId
      ImageType
      FileSystem
  deriving (Eq, Read, Show, Typeable, Data, Generic)

instance Hashable SharedImage

instance Binary SharedImage

instance NFData SharedImage

-- | The name of the image is the de-facto identifier for push, pull, 'From' and
--   'Share'.  B9 always selects the newest version the shared image identified
--   by that name when using a shared image as an 'ImageSource'. This is a
--   wrapper around a string that identifies a 'SharedImage'
newtype SharedImageName = SharedImageName String deriving (Eq, Ord, Read, Show, Typeable, Data, Hashable, Binary, NFData)

-- | Get the String representation of a 'SharedImageName'.
fromSharedImageName :: SharedImageName -> String
fromSharedImageName (SharedImageName b) = b

-- | The exact time that build job __started__.
--   This is a wrapper around a string contains the build date of a
--   'SharedImage'; this is purely additional convenience and typesafety
newtype SharedImageDate = SharedImageDate String deriving (Eq, Ord, Read, Show, Typeable, Data, Hashable, Binary, NFData)

-- | Every B9 build running in a 'B9Monad'
--   contains a random unique id that is generated once per build (no matter how
--   many artifacts are created in that build) This field contains the build id
--   of the build that created the shared image instance.  This is A wrapper
--   around a string contains the build id of a 'SharedImage'; this is purely
--   additional convenience and typesafety
newtype SharedImageBuildId = SharedImageBuildId String deriving (Eq, Ord, Read, Show, Typeable, Data, Hashable, Binary, NFData)

-- | Get the String representation of a 'SharedImageBuildId'.
fromSharedImageBuildId :: SharedImageBuildId -> String
fromSharedImageBuildId (SharedImageBuildId b) = b

-- | Shared images are ordered by name, build date and build id
instance Ord SharedImage where
  compare (SharedImage n d b _ _) (SharedImage n' d' b' _ _) =
    compare n n' Sem.<> compare d d' Sem.<> compare b b'

-- | Transform a list of 'SharedImage' values into a 'Map' that associates
-- each 'SharedImageName' with a 'Set' of the actual images with that name.
--
-- The 'Set' contains values of type  @'SharedImage'@.
--
-- The 'Ord' instance of 'SharedImage' sorts by name first and then by
-- 'sharedImageDate', since the values in a 'Set' share the same 'sharedImageName',
-- they are effectively orderd by build date, which is useful the shared image cleanup.
--
-- @since 1.1.0
sharedImagesToMap :: [SharedImage] -> Map SharedImageName (Set SharedImage)
sharedImagesToMap _ = error "IMPLEMENT ME"

-- | Return the 'SharedImage' with the highest 'sharedImageDate'.
--
-- @since 1.1.0
takeLatestSharedImage :: [SharedImage] -> Maybe SharedImage
takeLatestSharedImage _ss = do
  error "IMPLEMENT ME"

-- * Constructor and accessors for 'Image' 'ImageTarget' 'ImageSource'
-- 'ImageDestination' and 'SharedImage'

-- | Return the name of the file corresponding to an 'Image'
imageFileName :: Image -> FilePath
imageFileName (Image f _ _) = f

-- | Return the 'ImageType' of an 'Image'
imageImageType :: Image -> ImageType
imageImageType (Image _ t _) = t

-- | Return the files generated for a 'LocalFile' or a 'LiveInstallerImage'; 'SharedImage' and 'Transient'
-- are treated like they have no output files because the output files are manged
-- by B9.
getImageDestinationOutputFiles :: ImageTarget -> [FilePath]
getImageDestinationOutputFiles (ImageTarget d _ _) = case d of
  LiveInstallerImage liName liPath _ ->
    let path = liPath </> "machines" </> liName </> "disks" </> "raw"
     in [path </> "0.raw", path </> "0.size", path </> "VERSION"]
  LocalFile (Image lfPath _ _) _ -> [lfPath]
  _ -> []

-- | Return the name of a shared image, if the 'ImageDestination' is a 'Share'
--   destination
imageDestinationSharedImageName :: ImageDestination -> Maybe SharedImageName
imageDestinationSharedImageName (Share n _ _) = Just (SharedImageName n)
imageDestinationSharedImageName _ = Nothing

-- | Return the name of a shared source image, if the 'ImageSource' is a 'From'
--   source
imageSourceSharedImageName :: ImageSource -> Maybe SharedImageName
imageSourceSharedImageName (From n _) = Just (SharedImageName n)
imageSourceSharedImageName _ = Nothing

-- | Get the 'ImageDestination' of an 'ImageTarget'
itImageDestination :: ImageTarget -> ImageDestination
itImageDestination (ImageTarget d _ _) = d

-- | Get the 'ImageSource' of an 'ImageTarget'
itImageSource :: ImageTarget -> ImageSource
itImageSource (ImageTarget _ s _) = s

-- | Get the 'MountPoint' of an 'ImageTarget'
itImageMountPoint :: ImageTarget -> MountPoint
itImageMountPoint (ImageTarget _ _ m) = m

-- | Return true if a 'Partition' parameter is actually referring to a partition,
-- false if it is 'NoPT'
isPartitioned :: Partition -> Bool
isPartitioned p
  | p == NoPT = False
  | otherwise = True

-- | Return the 'Partition' index or throw a runtime error if applied to 'NoPT'
getPartition :: Partition -> Int
getPartition (Partition p) = p
getPartition NoPT = error "No partitions!"

-- | Return the file name extension of an image file with a specific image
-- format.
imageFileExtension :: ImageType -> String
imageFileExtension Raw = "raw"
imageFileExtension QCow2 = "qcow2"
imageFileExtension Vmdk = "vmdk"

-- | Change the image file format and also rename the image file name to
-- have the appropriate file name extension. See 'imageFileExtension' and
-- 'replaceExtension'
changeImageFormat :: ImageType -> Image -> Image
changeImageFormat fmt' (Image img _ fs) = Image img' fmt' fs
  where
    img' = replaceExtension img (imageFileExtension fmt')

changeImageDirectory :: FilePath -> Image -> Image
changeImageDirectory dir (Image img fmt fs) = Image img' fmt fs
  where
    img' = dir </> takeFileName img

-- * Constructors and accessors for 'ImageSource's

getImageSourceImageType :: ImageSource -> Maybe ImageType
getImageSourceImageType (EmptyImage _ _ t _) = Just t
getImageSourceImageType (CopyOnWrite i) = Just $ imageImageType i
getImageSourceImageType (SourceImage i _ _) = Just $ imageImageType i
getImageSourceImageType (From _ _) = Nothing

-- * Constructors and accessors for 'SharedImage's

-- | Return the name of a shared image.
sharedImageName :: SharedImage -> SharedImageName
sharedImageName (SharedImage n _ _ _ _) = n

-- | Return the build date of a shared image.
sharedImageDate :: SharedImage -> SharedImageDate
sharedImageDate (SharedImage _ n _ _ _) = n

-- | Return the build id of a shared image.
sharedImageBuildId :: SharedImage -> SharedImageBuildId
sharedImageBuildId (SharedImage _ _ n _ _) = n

-- | Print the contents of the shared image in one line
prettyPrintSharedImages :: Set SharedImage -> String
prettyPrintSharedImages imgs = Boxes.render table
  where
    table = Boxes.hsep 1 Boxes.left cols
      where
        cols = [nameC, dateC, idC]
          where
            nameC = col "Name" ((\(SharedImageName n) -> n) . sharedImageName)
            dateC = col "Date" ((\(SharedImageDate n) -> n) . sharedImageDate)
            idC =
              col
                "ID"
                ((\(SharedImageBuildId n) -> n) . sharedImageBuildId)
            col title accessor =
              Boxes.text title Boxes.// Boxes.vcat Boxes.left cells
              where
                cells = Boxes.text . accessor <$> Set.toList imgs

-- | Return the disk image of an sharedImage
sharedImageImage :: SharedImage -> Image
sharedImageImage (SharedImage (SharedImageName n) _ (SharedImageBuildId bid) sharedImageType sharedImageFileSystem) =
  Image
    (n ++ "_" ++ bid <.> imageFileExtension sharedImageType)
    sharedImageType
    sharedImageFileSystem

-- | Calculate the path to the text file holding the serialized 'SharedImage'
-- relative to the directory of shared images in a repository.
sharedImageFileName :: SharedImage -> FilePath
sharedImageFileName (SharedImage (SharedImageName n) _ (SharedImageBuildId bid) _ _) =
  n ++ "_" ++ bid <.> sharedImageFileExtension

sharedImagesRootDirectory :: FilePath
sharedImagesRootDirectory = "b9_shared_images"

sharedImageFileExtension :: String
sharedImageFileExtension = "b9si"

-- | The internal image type to use as best guess when dealing with a 'From'
-- value.
sharedImageDefaultImageType :: ImageType
sharedImageDefaultImageType = QCow2

-- * Constructors for 'ImageTarget's

-- | Use a 'QCow2' image with an 'Ext4' file system
transientCOWImage :: FilePath -> FilePath -> ImageTarget
transientCOWImage fileName mountPoint =
  ImageTarget
    Transient
    (CopyOnWrite (Image fileName QCow2 Ext4))
    (MountPoint mountPoint)

-- | Use a shared image
transientSharedImage :: SharedImageName -> FilePath -> ImageTarget
transientSharedImage (SharedImageName name) mountPoint =
  ImageTarget Transient (From name KeepSize) (MountPoint mountPoint)

-- | Use a shared image
transientLocalImage :: FilePath -> FilePath -> ImageTarget
transientLocalImage name mountPoint =
  ImageTarget Transient (From name KeepSize) (MountPoint mountPoint)

-- | Share a 'QCow2' image with 'Ext4' fs
shareCOWImage :: FilePath -> SharedImageName -> FilePath -> ImageTarget
shareCOWImage srcFilename (SharedImageName destName) mountPoint =
  ImageTarget
    (Share destName QCow2 KeepSize)
    (CopyOnWrite (Image srcFilename QCow2 Ext4))
    (MountPoint mountPoint)

-- | Share an image based on a shared image
shareSharedImage ::
  SharedImageName -> SharedImageName -> FilePath -> ImageTarget
shareSharedImage (SharedImageName srcName) (SharedImageName destName) mountPoint =
  ImageTarget
    (Share destName QCow2 KeepSize)
    (From srcName KeepSize)
    (MountPoint mountPoint)

-- | Share a 'QCow2' image with 'Ext4' fs
shareLocalImage :: FilePath -> SharedImageName -> FilePath -> ImageTarget
shareLocalImage srcName (SharedImageName destName) mountPoint =
  ImageTarget
    (Share destName QCow2 KeepSize)
    (SourceImage (Image srcName QCow2 Ext4) NoPT KeepSize)
    (MountPoint mountPoint)

-- | Export a 'QCow2' image with 'Ext4' fs
cowToliveInstallerImage ::
  String -> FilePath -> FilePath -> FilePath -> ImageTarget
cowToliveInstallerImage srcName destName outDir mountPoint =
  ImageTarget
    (LiveInstallerImage destName outDir KeepSize)
    (CopyOnWrite (Image srcName QCow2 Ext4))
    (MountPoint mountPoint)

-- | Export a 'QCow2' image file with 'Ext4' fs as
--   a local file
cowToLocalImage :: FilePath -> FilePath -> FilePath -> ImageTarget
cowToLocalImage srcName destName mountPoint =
  ImageTarget
    (LocalFile (Image destName QCow2 Ext4) KeepSize)
    (CopyOnWrite (Image srcName QCow2 Ext4))
    (MountPoint mountPoint)

-- | Export a 'QCow2' image file with 'Ext4' fs as
--   a local file
localToLocalImage :: FilePath -> FilePath -> FilePath -> ImageTarget
localToLocalImage srcName destName mountPoint =
  ImageTarget
    (LocalFile (Image destName QCow2 Ext4) KeepSize)
    (SourceImage (Image srcName QCow2 Ext4) NoPT KeepSize)
    (MountPoint mountPoint)

-- | Create a local image file from the contents of the first partition
--   of a local 'QCow2' image.
partition1ToLocalImage :: FilePath -> FilePath -> FilePath -> ImageTarget
partition1ToLocalImage srcName destName mountPoint =
  ImageTarget
    (LocalFile (Image destName QCow2 Ext4) KeepSize)
    (SourceImage (Image srcName QCow2 Ext4) NoPT KeepSize)
    (MountPoint mountPoint)

-- * 'ImageTarget' Transformations

-- | Split any image target into two image targets, one for creating an intermediate shared image and one
-- from the intermediate shared image to the output image.
splitToIntermediateSharedImage ::
  ImageTarget -> SharedImageName -> (ImageTarget, ImageTarget)
splitToIntermediateSharedImage (ImageTarget dst src mnt) (SharedImageName intermediateName) =
  (imgTargetShared, imgTargetExport)
  where
    imgTargetShared = ImageTarget intermediateTo src mnt
    imgTargetExport = ImageTarget dst intermediateFrom mnt
    intermediateTo =
      Share
        intermediateName
        (fromMaybe sharedImageDefaultImageType (getImageSourceImageType src))
        KeepSize
    intermediateFrom = From intermediateName KeepSize

-- * 'Arbitrary' instances for quickcheck

instance Arbitrary ImageTarget where
  arbitrary =
    ImageTarget
      <$> smaller arbitrary
      <*> smaller arbitrary
      <*> smaller arbitrary

instance Arbitrary ImageSource where
  arbitrary =
    oneof
      [ EmptyImage "img-label"
          <$> smaller arbitrary
          <*> smaller arbitrary
          <*> smaller arbitrary,
        CopyOnWrite <$> smaller arbitrary,
        SourceImage
          <$> smaller arbitrary
          <*> smaller arbitrary
          <*> smaller arbitrary,
        From <$> arbitrarySharedImageName <*> smaller arbitrary
      ]

instance Arbitrary ImageDestination where
  arbitrary =
    oneof
      [ Share
          <$> arbitrarySharedImageName
          <*> smaller arbitrary
          <*> smaller arbitrary,
        LiveInstallerImage "live-installer" "output-path"
          <$> smaller arbitrary,
        pure Transient
      ]

instance Arbitrary MountPoint where
  arbitrary = elements [MountPoint "/mnt", NotMounted]

instance Arbitrary ImageResize where
  arbitrary =
    oneof
      [ ResizeImage <$> smaller arbitrary,
        Resize <$> smaller arbitrary,
        ShrinkToMinimumAndIncrease <$> smaller arbitrary,
        pure ShrinkToMinimum,
        pure KeepSize
      ]

instance Arbitrary Partition where
  arbitrary = oneof [Partition <$> elements [0, 1, 2], pure NoPT]

instance Arbitrary Image where
  arbitrary =
    Image "img-file-name" <$> smaller arbitrary <*> smaller arbitrary

instance Arbitrary FileSystem where
  arbitrary = elements [Ext4]

instance Arbitrary ImageType where
  arbitrary = elements [Raw, QCow2, Vmdk]

instance Arbitrary ImageSize where
  arbitrary = ImageSize <$> smaller arbitrary <*> smaller arbitrary

instance Arbitrary SizeUnit where
  arbitrary = elements [KB, MB, GB]

instance Arbitrary SharedImageName where
  arbitrary = SharedImageName <$> arbitrarySharedImageName

arbitrarySharedImageName :: Gen String
arbitrarySharedImageName =
  elements [printf "arbitrary-shared-img-name-%d" x | x <- [0 :: Int .. 3]]

unitTests :: Spec
unitTests =
  describe "ImageSize"
    $ describe "bytesToKiloBytes"
    $ do
      it "accepts maxBound" $
        toInteger (imageSizeToKiB (bytesToKiloBytes maxBound)) * 1024 === toInteger (maxBound :: Int) + 1
      it "doesn't decrease in size" $
        property
          ( \(x :: Int) ->
              x <= maxBound - 1024 ==> label "bytesToKiloBytes x >= x" (imageSizeToKiB (bytesToKiloBytes x) >= (x `div` 1024))
          )
