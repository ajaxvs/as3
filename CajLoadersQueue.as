/**
 *
 * @author		Dmitriy Kravtsov <ajaxvs@gmail.com>
 * @version		1.0.0
 *  
 */

package ru.ajaxvs.android.loaders {
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	
	/**
	 * 
	 * flash.net.URLLoader doesn't handle a lot of bugs and errors.
	 * <br />You can get mass http status == 0, io errors etc so requested file won't be downloaded.
	 * <br />This class helps a lot. 
	 * <br />Don't forget to register global UncaughtErrorEvent for no-internet-connection flash URLLoader issue.
	 *  
	 */
	public class CajLoadersQueue {
		//========================================
		private const httpPrefix:String = "http"; //using for checking HTTPStatusEvent
		//========================================
		private var maxLoadersPerTime:int = 0;
		private var maxReloadsPerUrl:int = 5;
		private var aQueue:Vector.<CajLoadersJob> = new Vector.<CajLoadersJob>;
		private var aExecuteJobs:Vector.<CajLoadersJob> = new Vector.<CajLoadersJob>;
		private var lastErrorUrl:String = "";
		private var totalReloads:int = 0;
		//========================================
		public function CajLoadersQueue() {}
		//========================================
		/**
		 * sets optional vars.
		 * 
		 * @param maxLoadersPerTime set 0 if don't need any restrictions for loaders amount. Warning: can cause to mass HttpStatus == 0.
		 * @param maxReloadsPerUrl how many times file can be reloaded if errors happens.
		 * 
		 */
		public function config(maxLoadersPerTime:int, maxReloadsPerUrl:int):void {
			this.maxLoadersPerTime = maxLoadersPerTime;
			this.maxReloadsPerUrl = maxReloadsPerUrl;
		}
		//========================================
		/**
		 * removes all listeners from started loaders and clear the queues.
		 */
		public function clear():void {
			aQueue.splice(0, aQueue.length);
			
			for each (var job:CajLoadersJob in aExecuteJobs) {
				removeListeners(job.loader);
			}
			aExecuteJobs.splice(0, aExecuteJobs.length);
			
			lastErrorUrl = "";
			totalReloads = 0;
		}
		//========================================
		/*
		//========================================
		//global UncaughtErrorEvent:
		private function registerLoaderErrors():void {
			loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtErrorEvent);
		}		
		private function onUncaughtErrorEvent(err:UncaughtErrorEvent):void {
			err.preventDefault(); //don't show error msg f there's no internet connection
			trace("onUncaughtErrorEvent", err.text);
		}
		//========================================
		*/		
		/**
		 * Adds new loader to queue and starts loading if it's possible.
		 * <br />Use this function instead of URLLoader.load(URLRequest) for misc errors avoiding.
		 * <br />
		 * <br />Don't forget to register global UncaughtErrorEvent for no-internet-connection flash URLLoader issue.
		 * 
		 * <br />
		 * @param loader URLLoader. make sure you've set .dataFormat and other parameters.
		 * @param request URLRequest. make sure you've set .method and other parameters.
		 * @param onComplete main callback(complete:Event, url:String) or (null, url:String) if file is not available for downloading. 
		 * @param onIoError optional callback(e:IOErrorEvent, url:String)
		 * @param onSecurityError optional callback(e:SecurityErrorEvent, url:String)
		 * @param onStatus optional callback for both HTTPStatusEvent.HTTP_RESPONSE_STATUS and .HTTP_STATUS. same parameters.
		 * @param alreadyReloadTries
		 * 
		 */
		public function add(loader:URLLoader, request:URLRequest, onComplete:Function, onIoError:Function = null, onSecurityError:Function = null, onStatus:Function = null, alreadyReloadTries:int = 0):void {
			if (loader == null || request == null) {
				//throw new Error("incorrect parameters"); //rly?
				return;
			}
			
			var job:CajLoadersJob = findJob(loader, aQueue);
			
			if (job == null) {
				job = new CajLoadersJob(loader, request, onComplete, onIoError, onSecurityError, onStatus);
				aQueue.push(job);
			} else {
				job.loader = loader;
				job.request = request;
				job.onComplete = onComplete;
				job.onIoError = onIoError;
				job.onSecurityError = onSecurityError;
				job.onStatus = onStatus;
			}
			job.reloads = alreadyReloadTries;

			tryExecuteNewJob();
		}
		//========================================
		/**
		 * creates default new URLLoader() with URLLoaderDataFormat.TEXT from url parameter and URLRequest with URLRequestMethod.GET
		 * <br>then calls add()
		 * 
 		 * @param urlForTextFile url or file path
		 * @see CajLoadersQueue.add() 
		 */
		public function addUrl(urlForTextFile:String, onComplete:Function, onIoError:Function = null, onSecurityError:Function = null, onStatus:Function = null, alreadyReloadTries:int = 0):void {
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			var req:URLRequest = new URLRequest(urlForTextFile);
			req.method = URLRequestMethod.GET;
			add(loader, req, onComplete, onIoError, onSecurityError, onStatus, alreadyReloadTries);
		}
		//========================================
		/**
		 * cancels already started loader
		 *  
		 * @param loader URLLoader
		 * 
		 */
		public function cancel(loader:URLLoader):void {
			if (loader) {			
				var job:CajLoadersJob = findJob(loader, aExecuteJobs); 
				onJobFinish(job);
				
				remove(loader, aQueue);
			}				
		}
		//========================================
		/**
		 * 
		 * @return url of file that can not be downloaded (maxReloadsPerUrl times)
		 * @see CajLoadersQueue.config()  
		 * 
		 */
		public function getLastErrorUrl():String {
			return lastErrorUrl;
		}
		//========================================
		/**
		 * 
		 * @return total IOError, SecurityError, Status errors count from last clear() time. 
		 * @see CajLoadersQueue.clear()
		 */
		public function getTotalReloads():int {
			return totalReloads;
		}
		//========================================
		private function tryExecuteNewJob():void {
			var isQueue:Boolean = (aQueue.length > 0);
			var isFreeSlots:Boolean = (maxLoadersPerTime == 0) || (aExecuteJobs.length < maxLoadersPerTime);
			if (isQueue && isFreeSlots) {
				var job:CajLoadersJob = aQueue.shift();
				aExecuteJobs.push(job);
				
				var loader:URLLoader = job.loader;
				loader.addEventListener(Event.COMPLETE, onLoaderComplete);
				loader.addEventListener(IOErrorEvent.IO_ERROR, onLoaderIoError);
				loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onLoaderSecurityError);
				loader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, onLoaderStatus);
				loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, onLoaderStatus);
				//URLLoader doesn't dispatch ProgressEvent.Progress
				
				loader.load(job.request);
			}
		}
		//========================================
		private function remove(loader:URLLoader, aJobs:Vector.<CajLoadersJob>):void {
			for (var i:int = aJobs.length - 1; i >= 0; i--) {
				if (aJobs[i].loader == loader) {
					aJobs.splice(i, 1);
				}
			}
		}
		//========================================
		private function findJob(loader:URLLoader, aJobs:Vector.<CajLoadersJob>):CajLoadersJob {
			for each (var job:CajLoadersJob in aJobs) {
				if (job.loader == loader) {
					return job;
				}
			}
			return null;
		}
		//========================================
		private function removeListeners(loader:URLLoader):void {
			if (loader) {
				loader.removeEventListener(Event.COMPLETE, onLoaderComplete);
				loader.removeEventListener(IOErrorEvent.IO_ERROR, onLoaderIoError);
				loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onLoaderSecurityError);
				loader.removeEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, onLoaderStatus);
				loader.removeEventListener(HTTPStatusEvent.HTTP_STATUS, onLoaderStatus);
			}
		}
		//========================================
		private function onJobFinish(job:CajLoadersJob):void {
			var loader:URLLoader = job.loader;

			removeListeners(loader);			
			remove(job.loader, aExecuteJobs);
			
			//next one:
			tryExecuteNewJob();
		}
		//========================================
		private function onLoaderComplete(e:Event):void {
			var job:CajLoadersJob = findJob(e.target as URLLoader, aExecuteJobs);
			onJobFinish(job);
			
			if (job.onComplete != null) job.onComplete(e, job.request.url);
		}
		//========================================
		private function onLoaderIoError(e:IOErrorEvent):void {
			var job:CajLoadersJob = findJob(e.target as URLLoader, aExecuteJobs);
			
			reloadAttempt(job);
			
			if (job.onIoError != null) job.onIoError(e, job.request.url);
		}
		//========================================
		private function onLoaderSecurityError(e:SecurityErrorEvent):void {
			var job:CajLoadersJob = findJob(e.target as URLLoader, aExecuteJobs);
			
			reloadAttempt(job);
			
			if (job.onSecurityError != null) job.onSecurityError(e, job.request.url);
		}
		//========================================		
		private function onLoaderStatus(e:HTTPStatusEvent):void {
			var loader:URLLoader = e.target as URLLoader;
			var job:CajLoadersJob = findJob(loader, aExecuteJobs);
			
			const STATUS_OK:int = 200;
			if (e.status != STATUS_OK) {
				if (job.request.url.indexOf(httpPrefix) == 0) { //first symbol, so it's http:
					reloadAttempt(job);					
				}
			}
			
			if (job.onStatus != null) job.onStatus(e, job.request.url);
		}		
		//========================================
		private function reloadAttempt(job:CajLoadersJob):void {
			onJobFinish(job);
			
			if (job.reloads < maxReloadsPerUrl) {
				totalReloads++;
				job.reloads++;
				add(job.loader, job.request, job.onComplete, job.onIoError, job.onSecurityError, job.onStatus, job.reloads);
			} else {
				lastErrorUrl = job.request.url;
				job.onComplete(null, lastErrorUrl);
			}			
		}		
		//========================================
	}
}
