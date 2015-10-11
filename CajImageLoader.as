/**
 *
 * @author		Dmitriy Kravtsov <ajaxvs@gmail.com>
 * @version		1.0.0
 * 
 */

package ru.ajaxvs.android.starling {
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.JPEGEncoderOptions;
	import flash.display.PNGEncoderOptions;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.geom.Matrix;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.utils.ByteArray;
	
	import feathers.controls.ImageLoader;
	
	import starling.core.Starling;
	import starling.textures.Texture;
	import starling.utils.getNextPowerOfTwo;
	
	/**
	 * 
	 * Extension for feathers.controls.ImageLoader (Feathers 1.3+) class. This class offers:
	 * <br />
	 * <br />1. setMaxTextureSize() - sets max size for loading images (making thumbnails i.e.) 
	 * 			and prevents uncatchable "Texture is too big" error in original loader_completeHandler().  
	 * <br />2. saveLoadedBitmapData - sets if loaded BitmapData will be stored 
	 * 			regardless of Starling.handleLostContext. 
	 * <br />   getLoadedBitmapData() returns stored BitmapData.
	 * <br />3. getFullUrlSource() - returns string (original source url) if loaded image was URL file.
	 * <br />4. getLoadedTexture(). 
	 * <br />5. saveLoadedBitmapDataToFile().
	 * <br />6. cacheWebImage().
	 * 
	 * @see feathers.controls.ImageLoader
	 */
	public class CajImageLoader extends ImageLoader {
		//========================================
		//Don't forget about -swf-version.
		//it's static for memory saving. 
		/** using in saveLoadedBitmapDataToFile(). Users can create own Encoder objects, it's optional. */
		static public var saveBmdToFileJPEGEncoder:Object = null;
		static public var saveBmdToFilePNGEncoder:Object = null;		
		//========================================
		/** jpg quality for cache files. Default = 80 */
		public var saveFileJPEGQuality:Number = 80;
		/** if loaded BitmapData will be stored. Default = false */
		public var saveLoadedBitmapData:Boolean = false;
		/** if cached file can overwrite exist one. Default = true */
		public var rewriteCachedFile:Boolean = true;		
		//========================================
		/**
		 * World's default max texture size atm = 2048x2048.
		 * <br />
		 * <br />Note: 1024 * 4096 throws error on not so old devices. 1024x1024 is max size for first IPhones. 
		 * <br />So 2048x2048 is too big for default value.	
		 * */
		protected var maxTextureSize:int = 1024 * 1024;		
		/** using for crop if loaded image is too big. Here we can use 2048px as default max size. */
		protected var correctionBitmapSize:Point = new Point(2048, 2048);
		/** protected */		
		protected var loadedBitmapData:BitmapData = null;		
		protected var fullUrlSource:String = "";		
		//========================================
		/**
		 * constructor 
		 */
		public function CajImageLoader() {
			super();
		}
		//========================================
		/**
		 * prevents converting too big images to textures with uncatchable "Texture is too big" error.
		 *  
		 * @param size pixels per one side.
		 * 
		 */
		public function setMaxTextureSize(size:int):void {
			maxTextureSize = size * size;
			correctionBitmapSize.x = size;
			correctionBitmapSize.y = size;
		}
		//========================================
		/**
		 * @protected
		 */
		override protected function loader_completeHandler(event:Event):void {
			if (source is Texture) {
				//it's possible when ImageLoader is located in List item renderer for example. 
				//So when user scrolls list much faster than feathers can hanlde, such thing can happen
				trace("CajImageLoaderExt.loader_completeHandler() Error: ImageLoader.source is Texture");
				return; //np, image can be reloaded later
			}
			
			//getting bitmap and crop it if need:
			var bitmap:Bitmap = Bitmap(this.loader.content);
			if (getNextPowerOfTwo(bitmap.width) * getNextPowerOfTwo(bitmap.height) > maxTextureSize) {
				cropBitmapToCorrectionSize(bitmap);
			}

			//store bmd if need:
			onLoaderCompleteBitmapCorrection(bitmap);

			//super.loader_completeHandler(event); //no. we might changed bitmap. so from original ImageLoader:
			this.loader.contentLoaderInfo.removeEventListener(flash.events.Event.COMPLETE, loader_completeHandler);
			this.loader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			this.loader.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			this.loader = null;
			
			try {
				this.cleanupTexture();
				const bitmapData:BitmapData = bitmap.bitmapData;
				if(this._delayTextureCreation) {
					this._pendingBitmapDataTexture = bitmapData;
					if(this._textureQueueDuration < Number.POSITIVE_INFINITY) {
						this.addToTextureQueue();
					}
				} else {
					this.replaceBitmapDataTexture(bitmapData);
				}	
			} catch (err2:Error) {
				trace("CajImageLoaderExt.loader_completeHandler() Error2:", err2.message);
				trace(bitmap.width, bitmap.height, source, fullUrlSource);
			}
			
			//done. replaceBitmapDataTexture() dispatched starling.events.Event.COMPLETE. 
		}
		//========================================
		/**
		 * @protected
		 */		
		protected function cropBitmapToCorrectionSize(bitmap:Bitmap):void {
			//making bitmap smaller keeping aspect ratio:
			if (bitmap.width > correctionBitmapSize.x || bitmap.height > correctionBitmapSize.y) {
				var scale:Number = correctionBitmapSize.x / bitmap.width;
				var scaleH:Number = correctionBitmapSize.y / bitmap.height;
				if (scaleH < scale) scale = scaleH;
				
				var matrix:Matrix = new Matrix();
				matrix.scale(scale, scale);
				
				var newBmd:BitmapData = new BitmapData(bitmap.width * scale, bitmap.height * scale, true, 0);
				newBmd.draw(bitmap, matrix);
				
				bitmap.bitmapData = newBmd;
				bitmap.width = newBmd.width;
				bitmap.height = newBmd.height;
			}
		}
		//========================================
		/**
		 * @protected
		 */		
		protected function onLoaderCompleteBitmapCorrection(bitmap:Bitmap):void {
			if (saveLoadedBitmapData) {
				try {
					loadedBitmapData = new BitmapData(bitmap.width, bitmap.height, true, 0);
					loadedBitmapData.draw(bitmap);
				} catch (err1:Error) {
					trace("CajImageLoaderExt.loader_completeHandler() Error1:", err1.message);
				}
			}			
		}
		//========================================
		override public function set source(value:Object):void {
			if (value is String) {
				fullUrlSource = value as String;
			}
			super.source = value;
		}
		//========================================
		/**
		 * @return original source url if loaded image was URL file. 
		 */
		public function getFullUrlSource():String {
			return fullUrlSource;
		}
		//========================================
		/**
		 * @return original texture 
		 */
		public function getLoadedTexture():Texture {
			return _texture;
		}
		//========================================
		/**
		 * @return stored BitmapData if saveLoadedBitmapData or Starling.handleLostContext was set to true. 
		 * Otherwise returns null.
		 */
		public function getLoadedBitmapData():BitmapData {
			var bmd:BitmapData = loadedBitmapData;
			if (bmd == null && Starling.handleLostContext) {
				bmd = _textureBitmapData;
			}
			return bmd;
		}
		//========================================
		/**
		 * disposes loadedBitmapData if it was created. 
		 */
		public function disposeLoadedBitmapData():void {
			if (loadedBitmapData) {
				loadedBitmapData.dispose();
				loadedBitmapData = null;
			}
		}
		//========================================
		/**
		 * save loadedBitmapData or _textureBitmapData to file.
		 * <br />don't forget about -swf-version
		 * 
		 * @param filePath path to save
		 * @param encoderType "jpg" or "png". If encoderType == "" it uses encoder depends on filePath extension. 
		 * "jpg" is using by default.
		 *
		 * @return if file was saved successfully
		 * 
		 * @see saveBmdToFilePNGEncoder
		 * @see saveBmdToFileJPEGEncoder
		 * @see saveFileJPEGQuality
		 *  
		 */		
		public function saveLoadedBitmapDataToFile(filePath:String, encoderType:String = ""):Boolean {
			var ret:Boolean = false;
			var bmd:BitmapData = getLoadedBitmapData();
			if (bmd == null) {
				trace("saveLoadedBitmapDataToFile() - no bitmapData for saving.");
				ret = false;
			} else {
				try {
					var ba:ByteArray = new ByteArray();
					var encoderObj:Object;
					var rect:Rectangle = new Rectangle(0, 0, bmd.width, bmd.height);
					
					if (encoderType == "") {
						//getting file format from filePath:
						var pos:int = filePath.lastIndexOf(".");
						if (pos > -1) {
							encoderType = filePath.substr(pos + 1);
						}
					}
					
					//encode:
					if (encoderType == "png") {
						if (saveBmdToFilePNGEncoder == null) {
							saveBmdToFilePNGEncoder = new PNGEncoderOptions();
						}
						bmd.encode(rect, saveBmdToFilePNGEncoder, ba);
					} else {
						//jpeg by default:
						if (saveBmdToFileJPEGEncoder == null) {
							saveBmdToFileJPEGEncoder = new JPEGEncoderOptions(saveFileJPEGQuality);
						}
						bmd.encode(rect, saveBmdToFileJPEGEncoder, ba);
					}
					
					//save:
					const tmpSuffix:String = ".tmp1";
					var tmpFile:File = new File(filePath + tmpSuffix);
					var fileStream:FileStream = new FileStream();
					fileStream.open(tmpFile, FileMode.WRITE);
					fileStream.writeBytes(ba, 0, ba.length);
					fileStream.close();
					
					var file:File = new File(filePath);
					tmpFile.moveTo(file, true);
					
					ret = true;
					//done.
				} catch (err:Error) {
					ret = false;
					trace("saveLoadedBitmapDataToFile() Error: ", filePath, " ", err);					
				}
			}
			
			return ret;
		}
		//========================================
		/**
		 * Checks if image came from certain source:
		 * 
		 * @param webUrlPrefix i.e. "http" for web.
		 * @param filePath If so, save it to local file system (filePath).
		 * 
		 * @return false if file could be cached but wasn't cached. Otherwise if everything's ok, returns true.
		 * 
		 * @see rewriteCachedFile
		 * 
		 */
		public function cacheWebImage(webUrlPrefix:String, filePath:String):Boolean {			
			var ret:Boolean = false;
			
			try {
				var url:String = fullUrlSource.toLocaleLowerCase();
				if (url.indexOf(webUrlPrefix) == 0) {
					var file:File = new File(filePath);
					if (rewriteCachedFile || !file.exists) {
						ret = saveLoadedBitmapDataToFile(filePath);
					} else {
						ret = true;
					}
				}
			} catch (err:Error) {
				trace("cacheWebImage() error:", err);
				ret = false;
			}
			
			return ret;
		}
		//========================================
		/**
		 * If image was loaded from web so full url is like "http://www.ex.com/data/1.jpg":
		 * @return string like "http___www.ex.com_data_1.jpg" so it can be using for caching etc.
		 * 
		 */
		public function convertFileNameFromUrlPath():String {
			var ret:String = "";
			if (fullUrlSource != "") {
				ret = fullUrlSource.replace(/[^a-z0-9\.]/gi, "_");
			}
			return ret;
		}
		//========================================
	}
}
