/*! For license information please see LICENSES */
(window.webpackJsonp=window.webpackJsonp||[]).push([[16],{720:function(t,e,n){"use strict";var o=n(724),r=n(1),l=Object(r.b)({name:"Dimensions",data:function(){return{width:null,height:null}},computed:{dimensionObserver:function(){var t=this;return new o.a((function(e){window.requestAnimationFrame((function(){t.width=e[0].contentRect.width,t.height=e[0].contentRect.height}))}))}},mounted:function(){this.dimensionObserver.observe(this.$el)},destroyed:function(){this.dimensionObserver.disconnect()},render:function(){return this.$scopedSlots.default({width:this.width,height:this.height})}}),c=n(4),component=Object(c.a)(l,undefined,undefined,!1,null,null,null);e.a=component.exports},937:function(t,e,n){"use strict";n(938)},938:function(t,e,n){t.exports={}},966:function(t,e,n){"use strict";var o=n(914),r=n.n(o),l=n(1),c=n(292),d={name:"LocationSelector"};d.props={location:{type:Object,default:function(){return defaultLocation}},locations:{type:Array,required:!0}},d.setup=function(t,e){var n=e.emit,o=t;return{props:o,currentLocation:Object(l.i)(o.location),onUpdateLocation:function(t){n("updateLocation",t)}}},d.components=Object.assign({FormLabel:c.a,Multiselect:r.a},d.components);var f=d,h=n(4),component=Object(h.a)(f,(function(){var t=this,e=t.$createElement,n=t._self._c||e;return n("div",[n("FormLabel",[t._t("default")],2),t._v(" "),n("multiselect",{staticClass:"cursor-pointer",attrs:{disabled:t.props.locations.length<=1,options:t.props.locations,"select-label":"","allow-empty":!1,"custom-label":function(option){return option.identifier?t.$t("locationSelectOptions."+option.identifier):""},"track-by":"identifier","deselect-label":"",placeholder:"","internal-search":!1,searchable:!1,"selected-label":""},on:{select:t.onUpdateLocation},scopedSlots:t._u([{key:"option",fn:function(e){return[n("div",{staticClass:"option__desc"},[n("div",{staticClass:"option__title"},[t._v("\n          "+t._s(t.$t("locationSelectOptions."+e.option.identifier))+"\n          "),n("div",{staticClass:"text-sm mt-2 leading-relaxed break-words whitespace-normal"},[t._v("\n            "+t._s(e.option.description)+"\n          ")])])])]}}]),model:{value:t.currentLocation,callback:function(e){t.currentLocation=e},expression:"currentLocation"}})],1)}),[],!1,null,null,null);e.a=component.exports},967:function(t,e,n){"use strict";n(32),n(81),n(35),n(43),n(38);var o=n(142),r=n.n(o),l=n(1),c=n(914),d=n.n(c),f=n(289),h=n(292),v=n(124),m={name:"UrlInput"};m.props={apiError:{default:"",type:String},errorMessage:{default:"",type:String},url:{type:String,default:"https://"},protocols:{type:Array,default:function(){return["https","http"]}},notYetMonitored:{type:Boolean,default:!1}},m.setup=function(t,e){var o=e.emit,c=t,d=Object(l.l)().i18n,f=Object(l.i)(c.notYetMonitored?"https":Object(v.e)(c.url)||"https"),h=Object(l.i)(c.notYetMonitored?c.url||"":c.url.split("/")[2]||""),m=Object(l.i)(!0),w=Object(l.i)(c.errorMessage),O=Object(l.i)(""),_=r()((function(){var t=n(973);if(!(h.value.length<1)){var e=t.toUnicode(h.value);!function(t){t.includes("://")&&(f.value=t.split("://")[0]),h.value=t;var e=t.length?t:c.url;O.value=e.includes("://")?e:"".concat(f.value,"://").concat(e),o("urlInput",O.value)}(e);var r=function(t){return"www.example.com"===t?d.t("changeDomain"):0!==t.length||d.t("domainIsEmpty")}(e);w.value=!0===r?"":r,m.value=r,r!==m.value&&o("validationStatusChange",{status:!0===r,url:O.value,message:r})}}),500);return Object(l.s)([h,f],(function(){_()}),{immediate:!0}),{protocol:f,domainName:h,mutateErrorMessage:w}},m.components=Object.assign({FormLabel:h.a,Multiselect:d.a,InputField:f.a},m.components);var w=m,O=n(4),component=Object(O.a)(w,(function(){var t=this,e=t.$createElement,n=t._self._c||e;return n("div",{staticClass:"flex my-6 "},[n("div",{staticClass:"pr-4 w-[100px]"},[n("FormLabel",{staticClass:"capitalize"},[t._t("urlProtocol",(function(){return[t._v("\n        "+t._s(t.$t("protocol"))+"\n      ")]}))],2),t._v(" "),n("multiselect",{staticClass:"cursor-pointer",attrs:{options:t.protocols,"select-label":"","allow-empty":!1,"deselect-label":"",placeholder:"","internal-search":!1,searchable:!1,"selected-label":""},model:{value:t.protocol,callback:function(e){t.protocol=e},expression:"protocol"}})],1),t._v(" "),n("InputField",{staticClass:"flex-auto",attrs:{name:"url",type:"url",placeholder:t.$t("projectDomainPlaceholder"),"additional-error":t.apiError,error:t.mutateErrorMessage},model:{value:t.domainName,callback:function(e){t.domainName=e},expression:"domainName"}},[t._t("urlText",(function(){return[t._v("\n      "+t._s(t.$t("projectDomain"))+"\n    ")]}))],2)],1)}),[],!1,null,null,null);e.a=component.exports},973:function(t,e,n){(function(t,o){var r;!function(l){e&&e.nodeType,t&&t.nodeType;var c="object"==typeof o&&o;c.global!==c&&c.window!==c&&c.self;var d,f=2147483647,base=36,h=/^xn--/,v=/[^\x20-\x7E]/,m=/[\x2E\u3002\uFF0E\uFF61]/g,w={overflow:"Overflow: input needs wider integers to process","not-basic":"Illegal input >= 0x80 (not a basic code point)","invalid-input":"Invalid input"},O=Math.floor,_=String.fromCharCode;function j(t){throw new RangeError(w[t])}function map(t,e){for(var n=t.length,o=[];n--;)o[n]=e(t[n]);return o}function x(t,e){var n=t.split("@"),o="";return n.length>1&&(o=n[0]+"@",t=n[1]),o+map((t=t.replace(m,".")).split("."),e).join(".")}function y(t){for(var e,n,output=[],o=0,r=t.length;o<r;)(e=t.charCodeAt(o++))>=55296&&e<=56319&&o<r?56320==(64512&(n=t.charCodeAt(o++)))?output.push(((1023&e)<<10)+(1023&n)+65536):(output.push(e),o--):output.push(e);return output}function C(t){return map(t,(function(t){var output="";return t>65535&&(output+=_((t-=65536)>>>10&1023|55296),t=56320|1023&t),output+=_(t)})).join("")}function L(t,e){return t+22+75*(t<26)-((0!=e)<<5)}function E(t,e,n){var o=0;for(t=n?O(t/700):t>>1,t+=O(t/e);t>455;o+=base)t=O(t/35);return O(o+36*t/(t+38))}function F(input){var t,e,n,o,r,l,c,d,h,v,m,output=[],w=input.length,i=0,_=128,x=72;for((e=input.lastIndexOf("-"))<0&&(e=0),n=0;n<e;++n)input.charCodeAt(n)>=128&&j("not-basic"),output.push(input.charCodeAt(n));for(o=e>0?e+1:0;o<w;){for(r=i,l=1,c=base;o>=w&&j("invalid-input"),((d=(m=input.charCodeAt(o++))-48<10?m-22:m-65<26?m-65:m-97<26?m-97:base)>=base||d>O((f-i)/l))&&j("overflow"),i+=d*l,!(d<(h=c<=x?1:c>=x+26?26:c-x));c+=base)l>O(f/(v=base-h))&&j("overflow"),l*=v;x=E(i-r,t=output.length+1,0==r),O(i/t)>f-_&&j("overflow"),_+=O(i/t),i%=t,output.splice(i++,0,_)}return C(output)}function S(input){var t,e,n,o,r,l,c,q,d,h,v,m,w,x,C,output=[];for(m=(input=y(input)).length,t=128,e=0,r=72,l=0;l<m;++l)(v=input[l])<128&&output.push(_(v));for(n=o=output.length,o&&output.push("-");n<m;){for(c=f,l=0;l<m;++l)(v=input[l])>=t&&v<c&&(c=v);for(c-t>O((f-e)/(w=n+1))&&j("overflow"),e+=(c-t)*w,t=c,l=0;l<m;++l)if((v=input[l])<t&&++e>f&&j("overflow"),v==t){for(q=e,d=base;!(q<(h=d<=r?1:d>=r+26?26:d-r));d+=base)C=q-h,x=base-h,output.push(_(L(h+C%x,0))),q=O(C/x);output.push(_(L(q,0))),r=E(e,w,n==o),e=0,++n}++e,++t}return output.join("")}d={version:"1.4.1",ucs2:{decode:y,encode:C},decode:F,encode:S,toASCII:function(input){return x(input,(function(t){return v.test(t)?"xn--"+S(t):t}))},toUnicode:function(input){return x(input,(function(t){return h.test(t)?F(t.slice(4).toLowerCase()):t}))}},void 0===(r=function(){return d}.call(e,n,e,t))||(t.exports=r)}()}).call(this,n(171)(t),n(51))}}]);