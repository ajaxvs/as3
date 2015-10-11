/**
 *
 * @author		Dmitriy Kravtsov <ajaxvs@gmail.com>
 * @version		1.0.0
 *  
 */

package ru.ajaxvs.android.loaders {
	
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	
	internal class CajLoadersJob {
		//========================================
		public var loader:URLLoader;
		public var request:URLRequest;
		public var onComplete:Function;
		public var onIoError:Function;
		public var onSecurityError:Function;
		public var onStatus:Function;
		public var reloads:int = 0;
		//========================================
		public function CajLoadersJob(loader:URLLoader, request:URLRequest, onComplete:Function, onIoError:Function, onSecurityError:Function, onStatus:Function) {
			this.loader = loader;
			this.request = request;
			this.onComplete = onComplete;
			this.onIoError = onIoError;
			this.onSecurityError = onSecurityError;
			this.onStatus = onStatus;
		}
		//========================================
	}
}
