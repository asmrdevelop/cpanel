(window.webpackJsonp=window.webpackJsonp||[]).push([[99],{198:function(t,e,n){"use strict";n.d(e,"a",(function(){return c}));var r=n(701),o=n(111),c=function(){function t(){}return t.prototype.sendEvent=function(t){return o.a.resolve({reason:"NoopTransport: Event has been skipped because no Dsn is configured.",status:r.a.Skipped})},t.prototype.close=function(t){return o.a.resolve(!0)},t}()},249:function(t,e,n){"use strict";n.d(e,"b",(function(){return d})),n.d(e,"a",(function(){return l}));var r=n(2);function o(t){if(t.metadata&&t.metadata.sdk){var e=t.metadata.sdk;return{name:e.name,version:e.version}}}function c(t,e){return e?(t.sdk=t.sdk||{},t.sdk.name=t.sdk.name||e.name,t.sdk.version=t.sdk.version||e.version,t.sdk.integrations=Object(r.e)(t.sdk.integrations||[],e.integrations||[]),t.sdk.packages=Object(r.e)(t.sdk.packages||[],e.packages||[]),t):t}function d(t,e){var n=o(e),c="aggregates"in t?"sessions":"session";return{body:JSON.stringify(Object(r.a)(Object(r.a)({sent_at:(new Date).toISOString()},n&&{sdk:n}),e.forceEnvelope()&&{dsn:e.getDsn().toString()}))+"\n"+JSON.stringify({type:c})+"\n"+JSON.stringify(t),type:c,url:e.getEnvelopeEndpointWithUrlEncodedAuth()}}function l(t,e){var n=o(e),d=t.type||"event",l="transaction"===d||e.forceEnvelope(),v=t.debug_meta||{},f=v.transactionSampling,h=Object(r.d)(v,["transactionSampling"]),_=f||{},y=_.method,m=_.rate;0===Object.keys(h).length?delete t.debug_meta:t.debug_meta=h;var E={body:JSON.stringify(n?c(t,e.metadata.sdk):t),type:d,url:l?e.getEnvelopeEndpointWithUrlEncodedAuth():e.getStoreEndpointWithUrlEncodedAuth()};if(l){var O=JSON.stringify(Object(r.a)(Object(r.a)({event_id:t.event_id,sent_at:(new Date).toISOString()},n&&{sdk:n}),e.forceEnvelope()&&{dsn:e.getDsn().toString()}))+"\n"+JSON.stringify({type:d,sample_rates:[{id:y,rate:m}]})+"\n"+E.body;E.body=O}return E}},383:function(t,e,n){"use strict";n.d(e,"a",(function(){return r}));var r="6.13.3"},384:function(t,e,n){"use strict";n.d(e,"a",(function(){return c}));var r=n(703),o=n(79),c=function(){function t(t,e,n){void 0===e&&(e={}),this.dsn=t,this._dsnObject=new r.a(t),this.metadata=e,this._tunnel=n}return t.prototype.getDsn=function(){return this._dsnObject},t.prototype.forceEnvelope=function(){return!!this._tunnel},t.prototype.getBaseApiEndpoint=function(){var t=this.getDsn(),e=t.protocol?t.protocol+":":"",n=t.port?":"+t.port:"";return e+"//"+t.host+n+(t.path?"/"+t.path:"")+"/api/"},t.prototype.getStoreEndpoint=function(){return this._getIngestEndpoint("store")},t.prototype.getStoreEndpointWithUrlEncodedAuth=function(){return this.getStoreEndpoint()+"?"+this._encodedAuth()},t.prototype.getEnvelopeEndpointWithUrlEncodedAuth=function(){return this.forceEnvelope()?this._tunnel:this._getEnvelopeEndpoint()+"?"+this._encodedAuth()},t.prototype.getStoreEndpointPath=function(){var t=this.getDsn();return(t.path?"/"+t.path:"")+"/api/"+t.projectId+"/store/"},t.prototype.getRequestHeaders=function(t,e){var n=this.getDsn(),header=["Sentry sentry_version=7"];return header.push("sentry_client="+t+"/"+e),header.push("sentry_key="+n.publicKey),n.pass&&header.push("sentry_secret="+n.pass),{"Content-Type":"application/json","X-Sentry-Auth":header.join(", ")}},t.prototype.getReportDialogEndpoint=function(t){void 0===t&&(t={});var e=this.getDsn(),n=this.getBaseApiEndpoint()+"embed/error-page/",r=[];for(var o in r.push("dsn="+e.toString()),t)if("dsn"!==o)if("user"===o){if(!t.user)continue;t.user.name&&r.push("name="+encodeURIComponent(t.user.name)),t.user.email&&r.push("email="+encodeURIComponent(t.user.email))}else r.push(encodeURIComponent(o)+"="+encodeURIComponent(t[o]));return r.length?n+"?"+r.join("&"):n},t.prototype._getEnvelopeEndpoint=function(){return this._getIngestEndpoint("envelope")},t.prototype._getIngestEndpoint=function(t){return this._tunnel?this._tunnel:""+this.getBaseApiEndpoint()+this.getDsn().projectId+"/"+t+"/"},t.prototype._encodedAuth=function(){var t={sentry_key:this.getDsn().publicKey,sentry_version:"7"};return Object(o.f)(t)},t}()},385:function(t,e,n){"use strict";n.d(e,"a",(function(){return d}));var r=n(85),o=n(86),c=n(198),d=function(){function t(t){this._options=t,this._options.dsn||r.a.warn("No DSN provided, backend will not do anything."),this._transport=this._setupTransport()}return t.prototype.eventFromException=function(t,e){throw new o.a("Backend has to implement `eventFromException` method")},t.prototype.eventFromMessage=function(t,e,n){throw new o.a("Backend has to implement `eventFromMessage` method")},t.prototype.sendEvent=function(t){this._transport.sendEvent(t).then(null,(function(t){r.a.error("Error while sending event: "+t)}))},t.prototype.sendSession=function(t){this._transport.sendSession?this._transport.sendSession(t).then(null,(function(t){r.a.error("Error while sending session: "+t)})):r.a.warn("Dropping session because custom transport doesn't implement sendSession")},t.prototype.getTransport=function(){return this._transport},t.prototype._setupTransport=function(){return new c.a},t}()},386:function(t,e,n){"use strict";n.d(e,"a",(function(){return c}));var r=n(465),o=n(85);function c(t,e){var n;!0===e.debug&&o.a.enable();var c=Object(r.b)();null===(n=c.getScope())||void 0===n||n.update(e.initialScope);var d=new t(e);c.bindClient(d)}},408:function(t,e,n){"use strict";n.d(e,"a",(function(){return S}));var r=n(2),o=n(211),c=n(714),d=n(716),l=n(703),v=n(33),f=n(85),h=n(111),_=n(57),time=n(702),object=n(79),y=n(110),m=n(86),E=n(465),O=[];function j(t){return t.reduce((function(t,e){return t.every((function(t){return e.name!==t.name}))&&t.push(e),t}),[])}function w(t){var e={};return function(t){var e=t.defaultIntegrations&&Object(r.e)(t.defaultIntegrations)||[],n=t.integrations,o=Object(r.e)(j(e));Array.isArray(n)?o=Object(r.e)(o.filter((function(t){return n.every((function(e){return e.name!==t.name}))})),j(n)):"function"==typeof n&&(o=n(o),o=Array.isArray(o)?o:[o]);var c=o.map((function(i){return i.name})),d="Debug";return-1!==c.indexOf(d)&&o.push.apply(o,Object(r.e)(o.splice(c.indexOf(d),1))),o}(t).forEach((function(t){e[t.name]=t,function(t){-1===O.indexOf(t.name)&&(t.setupOnce(o.b,E.b),O.push(t.name),f.a.log("Integration installed: "+t.name))}(t)})),Object.defineProperty(e,"initialized",{value:!0}),e}var S=function(){function t(t,e){this._integrations={},this._numProcessing=0,this._backend=new t(e),this._options=e,e.dsn&&(this._dsn=new l.a(e.dsn))}return t.prototype.captureException=function(t,e,n){var r=this,o=e&&e.event_id;return this._process(this._getBackend().eventFromException(t,e).then((function(t){return r._captureEvent(t,e,n)})).then((function(t){o=t}))),o},t.prototype.captureMessage=function(t,e,n,r){var o=this,c=n&&n.event_id,d=Object(v.i)(t)?this._getBackend().eventFromMessage(String(t),e,n):this._getBackend().eventFromException(t,n);return this._process(d.then((function(t){return o._captureEvent(t,n,r)})).then((function(t){c=t}))),c},t.prototype.captureEvent=function(t,e,n){var r=e&&e.event_id;return this._process(this._captureEvent(t,e,n).then((function(t){r=t}))),r},t.prototype.captureSession=function(t){this._isEnabled()?"string"!=typeof t.release?f.a.warn("Discarded session because of missing or non-string release"):(this._sendSession(t),t.update({init:!1})):f.a.warn("SDK not enabled, will not capture session.")},t.prototype.getDsn=function(){return this._dsn},t.prototype.getOptions=function(){return this._options},t.prototype.getTransport=function(){return this._getBackend().getTransport()},t.prototype.flush=function(t){var e=this;return this._isClientDoneProcessing(t).then((function(n){return e.getTransport().close(t).then((function(t){return n&&t}))}))},t.prototype.close=function(t){var e=this;return this.flush(t).then((function(t){return e.getOptions().enabled=!1,t}))},t.prototype.setupIntegrations=function(){this._isEnabled()&&!this._integrations.initialized&&(this._integrations=w(this._options))},t.prototype.getIntegration=function(t){try{return this._integrations[t.id]||null}catch(e){return f.a.warn("Cannot retrieve integration "+t.id+" from the current Client"),null}},t.prototype._updateSessionFromEvent=function(t,e){var n,o,d=!1,l=!1,v=e.exception&&e.exception.values;if(v){l=!0;try{for(var f=Object(r.f)(v),h=f.next();!h.done;h=f.next()){var _=h.value.mechanism;if(_&&!1===_.handled){d=!0;break}}}catch(t){n={error:t}}finally{try{h&&!h.done&&(o=f.return)&&o.call(f)}finally{if(n)throw n.error}}}var y=t.status===c.a.Ok;(y&&0===t.errors||y&&d)&&(t.update(Object(r.a)(Object(r.a)({},d&&{status:c.a.Crashed}),{errors:t.errors||Number(l||d)})),this.captureSession(t))},t.prototype._sendSession=function(t){this._getBackend().sendSession(t)},t.prototype._isClientDoneProcessing=function(t){var e=this;return new h.a((function(n){var r=0,o=setInterval((function(){0==e._numProcessing?(clearInterval(o),n(!0)):(r+=1,t&&r>=t&&(clearInterval(o),n(!1)))}),1)}))},t.prototype._getBackend=function(){return this._backend},t.prototype._isEnabled=function(){return!1!==this.getOptions().enabled&&void 0!==this._dsn},t.prototype._prepareEvent=function(t,e,n){var c=this,d=this.getOptions().normalizeDepth,l=void 0===d?3:d,v=Object(r.a)(Object(r.a)({},t),{event_id:t.event_id||(n&&n.event_id?n.event_id:Object(_.i)()),timestamp:t.timestamp||Object(time.a)()});this._applyClientOptions(v),this._applyIntegrationsMetadata(v);var f=e;n&&n.captureContext&&(f=o.a.clone(f).update(n.captureContext));var y=h.a.resolve(v);return f&&(y=f.applyToEvent(v,n)),y.then((function(t){return"number"==typeof l&&l>0?c._normalizeEvent(t,l):t}))},t.prototype._normalizeEvent=function(t,e){if(!t)return null;var n=Object(r.a)(Object(r.a)(Object(r.a)(Object(r.a)(Object(r.a)({},t),t.breadcrumbs&&{breadcrumbs:t.breadcrumbs.map((function(b){return Object(r.a)(Object(r.a)({},b),b.data&&{data:Object(object.d)(b.data,e)})}))}),t.user&&{user:Object(object.d)(t.user,e)}),t.contexts&&{contexts:Object(object.d)(t.contexts,e)}),t.extra&&{extra:Object(object.d)(t.extra,e)});t.contexts&&t.contexts.trace&&(n.contexts.trace=t.contexts.trace);var o=this.getOptions()._experiments;return(void 0===o?{}:o).ensureNoCircularStructures?Object(object.d)(n):n},t.prototype._applyClientOptions=function(t){var e=this.getOptions(),n=e.environment,r=e.release,o=e.dist,c=e.maxValueLength,d=void 0===c?250:c;"environment"in t||(t.environment="environment"in e?n:"production"),void 0===t.release&&void 0!==r&&(t.release=r),void 0===t.dist&&void 0!==o&&(t.dist=o),t.message&&(t.message=Object(y.d)(t.message,d));var l=t.exception&&t.exception.values&&t.exception.values[0];l&&l.value&&(l.value=Object(y.d)(l.value,d));var v=t.request;v&&v.url&&(v.url=Object(y.d)(v.url,d))},t.prototype._applyIntegrationsMetadata=function(t){var e=Object.keys(this._integrations);e.length>0&&(t.sdk=t.sdk||{},t.sdk.integrations=Object(r.e)(t.sdk.integrations||[],e))},t.prototype._sendEvent=function(t){this._getBackend().sendEvent(t)},t.prototype._captureEvent=function(t,e,n){return this._processEvent(t,e,n).then((function(t){return t.event_id}),(function(t){f.a.error(t)}))},t.prototype._processEvent=function(t,e,n){var r,o,c=this,l=this.getOptions(),v=l.beforeSend,f=l.sampleRate,_=this.getTransport();if(!this._isEnabled())return h.a.reject(new m.a("SDK not enabled, will not capture event."));var y="transaction"===t.type;return!y&&"number"==typeof f&&Math.random()>f?(null===(o=(r=_).recordLostEvent)||void 0===o||o.call(r,d.a.SampleRate,"event"),h.a.reject(new m.a("Discarding event because it's not included in the random sample (sampling rate = "+f+")"))):this._prepareEvent(t,n,e).then((function(n){var r,o;if(null===n)throw null===(o=(r=_).recordLostEvent)||void 0===o||o.call(r,d.a.EventProcessor,t.type||"event"),new m.a("An event processor returned null, will not send event.");if(e&&e.data&&!0===e.data.__sentry__||y||!v)return n;var l=v(n,e);return c._ensureBeforeSendRv(l)})).then((function(e){var r,o;if(null===e)throw null===(o=(r=_).recordLostEvent)||void 0===o||o.call(r,d.a.BeforeSend,t.type||"event"),new m.a("`beforeSend` returned `null`, will not send event.");var l=n&&n.getSession&&n.getSession();return!y&&l&&c._updateSessionFromEvent(l,e),c._sendEvent(e),e})).then(null,(function(t){if(t instanceof m.a)throw t;throw c.captureException(t,{data:{__sentry__:!0},originalException:t}),new m.a("Event processing pipeline threw an error, original event will not be sent. Details have been sent as a new event.\nReason: "+t)}))},t.prototype._process=function(t){var e=this;this._numProcessing+=1,t.then((function(t){return e._numProcessing-=1,t}),(function(t){return e._numProcessing-=1,t}))},t.prototype._ensureBeforeSendRv=function(t){var e="`beforeSend` method has to return `null` or a valid event.";if(Object(v.m)(t))return t.then((function(t){if(!Object(v.h)(t)&&null!==t)throw new m.a(e);return t}),(function(t){throw new m.a("beforeSend rejected with "+t)}));if(!Object(v.h)(t)&&null!==t)throw new m.a(e);return t},t}()},55:function(t,e,n){"use strict";n.d(e,"a",(function(){return o}));var r,o={};n.r(o),n.d(o,"FunctionToString",(function(){return c})),n.d(o,"InboundFilters",(function(){return m}));var c=function(){function t(){this.name=t.id}return t.prototype.setupOnce=function(){r=Function.prototype.toString,Function.prototype.toString=function(){for(var t=[],e=0;e<arguments.length;e++)t[e]=arguments[e];var n=this.__sentry_original__||this;return r.apply(n,t)}},t.id="FunctionToString",t}(),d=n(2),l=n(211),v=n(465),f=n(85),h=n(57),_=n(110),y=[/^Script error\.?$/,/^Javascript error: Script error\.? on line 0$/],m=function(){function t(e){void 0===e&&(e={}),this._options=e,this.name=t.id}return t.prototype.setupOnce=function(){Object(l.b)((function(e){var n=Object(v.b)();if(!n)return e;var r=n.getIntegration(t);if(r){var o=n.getClient(),c=o?o.getOptions():{},d="function"==typeof r._mergeOptions?r._mergeOptions(c):{};return"function"!=typeof r._shouldDropEvent?e:r._shouldDropEvent(e,d)?null:e}return e}))},t.prototype._shouldDropEvent=function(t,e){return this._isSentryError(t,e)?(f.a.warn("Event dropped due to being internal Sentry Error.\nEvent: "+Object(h.d)(t)),!0):this._isIgnoredError(t,e)?(f.a.warn("Event dropped due to being matched by `ignoreErrors` option.\nEvent: "+Object(h.d)(t)),!0):this._isDeniedUrl(t,e)?(f.a.warn("Event dropped due to being matched by `denyUrls` option.\nEvent: "+Object(h.d)(t)+".\nUrl: "+this._getEventFilterUrl(t)),!0):!this._isAllowedUrl(t,e)&&(f.a.warn("Event dropped due to not being matched by `allowUrls` option.\nEvent: "+Object(h.d)(t)+".\nUrl: "+this._getEventFilterUrl(t)),!0)},t.prototype._isSentryError=function(t,e){if(!e.ignoreInternal)return!1;try{return t&&t.exception&&t.exception.values&&t.exception.values[0]&&"SentryError"===t.exception.values[0].type||!1}catch(t){return!1}},t.prototype._isIgnoredError=function(t,e){return!(!e.ignoreErrors||!e.ignoreErrors.length)&&this._getPossibleEventMessages(t).some((function(t){return e.ignoreErrors.some((function(pattern){return Object(_.a)(t,pattern)}))}))},t.prototype._isDeniedUrl=function(t,e){if(!e.denyUrls||!e.denyUrls.length)return!1;var n=this._getEventFilterUrl(t);return!!n&&e.denyUrls.some((function(pattern){return Object(_.a)(n,pattern)}))},t.prototype._isAllowedUrl=function(t,e){if(!e.allowUrls||!e.allowUrls.length)return!0;var n=this._getEventFilterUrl(t);return!n||e.allowUrls.some((function(pattern){return Object(_.a)(n,pattern)}))},t.prototype._mergeOptions=function(t){return void 0===t&&(t={}),{allowUrls:Object(d.e)(this._options.whitelistUrls||[],this._options.allowUrls||[],t.whitelistUrls||[],t.allowUrls||[]),denyUrls:Object(d.e)(this._options.blacklistUrls||[],this._options.denyUrls||[],t.blacklistUrls||[],t.denyUrls||[]),ignoreErrors:Object(d.e)(this._options.ignoreErrors||[],t.ignoreErrors||[],y),ignoreInternal:void 0===this._options.ignoreInternal||this._options.ignoreInternal}},t.prototype._getPossibleEventMessages=function(t){if(t.message)return[t.message];if(t.exception)try{var e=t.exception.values&&t.exception.values[0]||{},n=e.type,r=void 0===n?"":n,o=e.value,c=void 0===o?"":o;return[""+c,r+": "+c]}catch(e){return f.a.error("Cannot extract message for event "+Object(h.d)(t)),[]}return[]},t.prototype._getLastValidUrl=function(t){var e,n;void 0===t&&(t=[]);for(var i=t.length-1;i>=0;i--){var r=t[i];if("<anonymous>"!==(null===(e=r)||void 0===e?void 0:e.filename)&&"[native code]"!==(null===(n=r)||void 0===n?void 0:n.filename))return r.filename||null}return null},t.prototype._getEventFilterUrl=function(t){try{if(t.stacktrace){var e=t.stacktrace.frames;return this._getLastValidUrl(e)}if(t.exception){var n=t.exception.values&&t.exception.values[0].stacktrace&&t.exception.values[0].stacktrace.frames;return this._getLastValidUrl(n)}return null}catch(e){return f.a.error("Cannot extract url for event "+Object(h.d)(t)),null}},t.id="InboundFilters",t}()}}]);