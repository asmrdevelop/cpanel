(window.webpackJsonp=window.webpackJsonp||[]).push([[90],{1007:function(e,t,n){"use strict";n(953)},1008:function(e,t,n){"use strict";var r=n(9),o=(n(25),n(38),n(35),n(43),n(60)),l=n.n(o),c=n(167),d=n(1),m=n(21),f=n(136);t.a=function(){var e=Object(d.l)().$apiClient,t=Object(d.p)(),n=Object(d.r)(),o="360LoginPath",h=Object(f.b)(),v="".concat(document.location.protocol,"//").concat(h),w=Object(m.f)(),_=Object(m.i)(),x=function(){var path=window.sessionStorage.getItem(o);return window.sessionStorage.removeItem(o),path},y=function(){var o=Object(r.a)(regeneratorRuntime.mark((function r(){var o,d,f,h,path;return regeneratorRuntime.wrap((function(r){for(;;)switch(r.prev=r.next){case 0:return r.prev=0,r.next=3,c.e.connect(e,{withMemories:!0});case 3:r.next=9;break;case 5:return r.prev=5,r.t0=r.catch(0),console.error(r.t0),r.abrupt("return",!1);case 9:return o=new c.e(Object(m.c)(),l.a),r.next=12,o.getSessionToken();case 12:if(d=r.sent,f=d.sessionToken,h=d.timezone,!f){r.next=25;break}return path=x()||"/dashboard",r.next=19,n.dispatch("access/loginUser",{sessionToken:f});case 19:return r.next=21,n.dispatch("access/setTimezone",h);case 21:return t.push({path:path}),r.abrupt("return",!0);case 25:return r.abrupt("return",!1);case 26:case"end":return r.stop()}}),r,null,[[0,5]])})));return function(){return o.apply(this,arguments)}}();return{connectWithSession:y,pathBeforeLogin:x,ssoLoginWithSavedPath:function(){var e=x();return(null==_?void 0:_.includes("?redirectUrl="))?"".concat(_).concat(v).concat(e||""):_||""},config:w,fullDomain:v}}},1025:function(e,t,n){"use strict";n(17),n(19),n(35),n(43);var r=n(1),o=n(915),l=n(916),c=n(9),d=(n(25),n(60)),m=n.n(d),f=n(149),h=n(289),v=n(112),w=(n(32),n(69),n(21)),_=Object(r.b)({name:"SSOLoginButton",props:{loginWith:{type:String,default:""},type:{type:String,default:"login"},isDisabled:{type:Boolean,default:!1}},setup:function(e){var t=Object(r.l)().i18n,n=Object(w.f)();return{buttonLabel:Object(r.a)((function(){return"login"===e.type?"hb"===e.loginWith?t.t("hb.login"):t.t("google.login"):"hb"===e.loginWith?t.t("hb.register"):t.t("google.register")})),logon:function(){if(e.loginWith){var t={google:n.ssoGoogle||"",hb:n.ssoAuth0||""};location.replace(t[e.loginWith])}}}}}),x=n(4),y=Object(x.a)(_,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("div",{staticClass:"rounded overflow-hidden text-white flex items-stretch h-12 bg-primary-hb hover:bg-primary-regular transition ease-in-out duration-300 cursor-pointer",class:[e.isDisabled?"opacity-50 pointer-events-none":""],on:{click:e.logon}},[n("div",{staticClass:"bg-primary-500 flex-center w-12 items-center"},[n("svg",{staticClass:"w-4",attrs:{fill:"currentColor",xmlns:"http://www.w3.org/2000/svg",viewBox:"0 0 195 199"}},["hb"===e.loginWith?n("path",{attrs:{"fill-rule":"evenodd","clip-rule":"evenodd",d:"M90.56 74.16c-3.21 10.79-6.37 21.6-9.48 32.42l-.4 1.34c-3.74 13.14-6.08 21.89-7 26.21-2.35 11.03 4.88 26.66 24.6 26.66 13.15 0 25.12-4.16 35.9-12.44l20.54 28.47c-6.13 6.6-15.34 12.5-27.64 17.7-31.2 8.38-61.28 3.04-75.64-11.84-13.26-12.65-16.54-37.03-13.26-50.75 2.2-9.16 7.5-28.4 15.9-57.78h36.48zM68.34 3.95C99.54-4.4 129.62.93 143.98 15.8c13.26 12.65 16.54 37.04 13.26 50.76-2.06 8.6-6.87 26.13-14.4 52.6l-.5 1.7-.99 3.47h-36.5c9.7-32.64 15.33-52.64 16.9-59.98 2.35-11.04-4.89-26.65-24.6-26.65-13.16 0-25.12 4.13-35.9 12.42L40.7 21.68c6.13-6.6 15.34-12.5 27.64-17.7z"}}):e._e(),e._v(" "),"google"===e.loginWith?n("path",{attrs:{d:"M195 101.31c0 56.5-38.72 96.69-95.9 96.69A98.93 98.93 0 010 99C0 44.23 44.27 0 99.1 0c26.7 0 49.15 9.78 66.45 25.9l-26.97 25.92C103.29 17.8 37.68 43.35 37.68 99c0 34.53 27.61 62.51 61.42 62.51 39.24 0 53.94-28.1 56.26-42.67H99.1V84.79h94.34A86.71 86.71 0 01195 101.3z"}}):e._e()])]),e._v(" "),n("div",{staticClass:"h-full flex items-center px-4 text-sm"},[e._v("\n    "+e._s(e.buttonLabel)+"\n  ")])])}),[],!1,null,null,null).exports,O=n(80),j=Object(r.b)({name:"LoginBoxRegister",components:{GeneralButton:O.a,Richtext:v.a,InputField:h.a,HeightExpander:f.a,SSOLoginButton:y},data:function(){return{acceptRules:!1,isRegistered:!1,apiError:null,form:{email:null,company:null,password:null,fullName:null},registerInfo:[{headline:"register.facts.firstHeadline",body:"register.facts.firstBody"},{headline:"register.facts.secondHeadline",body:"register.facts.secondBody"},{headline:"register.facts.thirdHeadline",body:"register.facts.thirdBody"}]}},computed:{checkEmail:function(){var e=this.form.email;return e?e.length>3&&/^(([^<>()[\]\\.,;:\s@"]+(\.[^<>()[\]\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/.test(e):null},checkPassword:function(){var e=this.form.password;return e?e.length>=3&&e.length<=300:null},successAllRequiredChecks:function(){return this.acceptRules&&this.checkEmail&&this.checkPassword}},mounted:function(){var e,t=this.$route.query;(null===(e=t.email)||void 0===e?void 0:e.length)&&(this.form.email=t.email),Object.keys(t).includes("email")&&(this.form.email=t.email)},methods:{closeRegister:function(){this.clearForm(),this.isRegistered=!1,this.apiError=null,this.$emit("cancelRegister")},clearForm:function(){this.form={email:null,username:null,fullName:null,company:null,password:null}},registerUser:function(){var e=this;return Object(c.a)(regeneratorRuntime.mark((function t(){var n;return regeneratorRuntime.wrap((function(t){for(;;)switch(t.prev=t.next){case 0:if(!e.successAllRequiredChecks){t.next=18;break}return e.apiError=null,t.prev=2,t.next=5,e.$apiClient.connect({accessToken:Object(w.d)(),axios:m.a});case 5:return t.next=7,e.$apiClient.getRepository("user");case 7:return n=t.sent,t.next=10,n.createUser(Object(w.f)().apiApplication,{email:e.form.email,userName:e.form.email,fullName:e.form.fullName,password:e.form.password,preferredLanguage:e.$i18n.locale});case 10:e.isRegistered=!0,e.$emit("isRegistered"),t.next=18;break;case 14:t.prev=14,t.t0=t.catch(2),e.apiError=t.t0.message,console.error(t.t0);case 18:case"end":return t.stop()}}),t,null,[[2,14]])})))()}}}),k=Object(x.a)(j,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("HeightExpander",[n("div",{staticClass:"md:flex items-center"},[e.isRegistered?n("div",{staticClass:"p-6"},[n("img",{staticClass:"mb-6",attrs:{src:"/ui/mailNotification.png",alt:""}}),e._v(" "),n("h2",{staticClass:"font-medium text-lg mb-4"},[e._v("\n        "+e._s(e.$t("register.checkMails"))+"\n      ")]),e._v(" "),n("p",{staticClass:"font-light leading-loose"},[n("Richtext",{attrs:{content:e.$t("register.checkMailsSentence")}})],1)]):[n("div",{staticClass:"md:w-1/2 px-4"},[n("InputField",{attrs:{"data-cy":"fullnameLastname",name:"fullname","inset-label":!0},model:{value:e.form.fullName,callback:function(t){e.$set(e.form,"fullName",t)},expression:"form.fullName"}},[e._v("\n          "+e._s(e.$t("register.fullName"))+"\n        ")]),e._v(" "),n("InputField",{attrs:{name:"email",error:e.form.email&&!e.checkEmail?e.$t("emailFormatNotValid"):"","inset-label":!0,required:!0,debouncer:!0},model:{value:e.form.email,callback:function(t){e.$set(e.form,"email",t)},expression:"form.email"}},[e._v("\n          "+e._s(e.$t("register.email"))+"\n        ")]),e._v(" "),n("InputField",{attrs:{name:"password",type:"password",error:e.form.password&&!e.checkPassword?e.$t("passwordMustBetween"):"","inset-label":!0,required:!0,debouncer:!0},model:{value:e.form.password,callback:function(t){e.$set(e.form,"password",t)},expression:"form.password"}},[e._v("\n          "+e._s(e.$t("register.password"))+"\n        ")]),e._v(" "),e.apiError?n("div",{staticClass:"text-sm text-error-high mt-4"},[e._v("\n          "+e._s(e.apiError)+"\n        ")]):e._e(),e._v(" "),n("div",{staticClass:"mt-4 text-sm"},[n("p",{staticClass:"text-medium"},[e._v("\n            "+e._s(e.$t("acceptRegisterHeadline"))+"\n          ")]),e._v(" "),n("p",{staticClass:"font-light mb-4 text-xs"},[e._v("\n            "+e._s(e.$t("acceptRegisterSubline"))+"\n          ")]),e._v(" "),n("div",{staticClass:"font-light text-sm flex"},[n("input",{directives:[{name:"model",rawName:"v-model",value:e.acceptRules,expression:"acceptRules"}],staticClass:"mr-1 cursor-pointer",staticStyle:{"margin-top":"3px"},attrs:{id:"acceptRules",type:"checkbox"},domProps:{checked:Array.isArray(e.acceptRules)?e._i(e.acceptRules,null)>-1:e.acceptRules},on:{change:function(t){var n=e.acceptRules,r=t.target,o=!!r.checked;if(Array.isArray(n)){var l=e._i(n,null);r.checked?l<0&&(e.acceptRules=n.concat([null])):l>-1&&(e.acceptRules=n.slice(0,l).concat(n.slice(l+1)))}else e.acceptRules=o}}}),e._v(" "),n("label",{attrs:{for:"acceptRules"}},[n("Richtext",{attrs:{content:e.$t("acceptRegisterRules")}})],1)])]),e._v(" "),n("GeneralButton",{staticClass:"mt-6 w-full",attrs:{"is-disabled":!e.successAllRequiredChecks,size:"p-4"},nativeOn:{click:function(t){return e.registerUser.apply(null,arguments)}}},[e._v("\n          "+e._s(e.$t("RegisterForFree"))+"\n        ")]),e._v(" "),n("div",{staticClass:"py-3 flex justify-center text-sm"},[e._v("\n          "+e._s(e.$t("or"))+"\n        ")]),e._v(" "),n("SSOLoginButton",{staticClass:"mb-4",attrs:{"login-with":"google",type:"register","is-disabled":!e.acceptRules}}),e._v(" "),n("div",{staticClass:"md:hidden font-light text-center text-gray-600"},[e._v("\n          "+e._s(e.$t("register.facts.firstBody"))+"\n        ")]),e._v(" "),n("div",{staticClass:"text-center mt-8  font-light"},[e._v("\n          "+e._s(e.$t("youHaveAnAccount"))+" "),n("span",{staticClass:"cursor-pointer font-medium hover:underline inline-block",attrs:{"data-cy":"loginbutton"},on:{click:e.closeRegister}},[e._v(e._s(e.$t("loginNow"))+".")])])],1),e._v(" "),n("div",{staticClass:"hidden md:block w-1/2 px-4"},[n("div",{staticClass:"ml-8"},[n("h2",{staticClass:"mb-8 font-medium text-lg"},[e._v("\n            "+e._s(e.$t("createFreeAccount"))+"\n          ")]),e._v(" "),n("ul",{staticClass:"list-disc font-light"},e._l(e.registerInfo,(function(t,r){return n("li",{key:r,staticClass:"ml-4 mb-6"},[n("h3",{staticClass:" mb-2"},[e._v("\n                "+e._s(e.$t(t.headline))+"\n              ")]),e._v(" "),n("p",{staticClass:"leading-relaxed text-sm"},[e._v("\n                "+e._s(e.$t(t.body))+"\n              ")])])})),0)])])]],2)])}),[],!1,null,null,null),C=k.exports,$=(n(16),n(15),n(27),n(28),n(11)),R=n(36),L={name:"FormErrorHandler",props:{error:{type:String,default:""}}},P=Object(x.a)(L,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return e.error?n("div",{staticClass:"text-sm text-red-500 text-center p-1 border border-red-200 bg-red-100"},[e._v("\n  "+e._s(e.error)+"\n")]):e._e()}),[],!1,null,null,null).exports;function S(object,e){var t=Object.keys(object);if(Object.getOwnPropertySymbols){var n=Object.getOwnPropertySymbols(object);e&&(n=n.filter((function(e){return Object.getOwnPropertyDescriptor(object,e).enumerable}))),t.push.apply(t,n)}return t}function B(e){for(var i=1;i<arguments.length;i++){var source=null!=arguments[i]?arguments[i]:{};i%2?S(Object(source),!0).forEach((function(t){Object($.a)(e,t,source[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(source)):S(Object(source)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(source,t))}))}return e}var E=Object(r.b)({name:"LoginBoxManualLogin",components:{GeneralButton:O.a,FormErrorHandler:P,InputField:h.a,HeightExpander:f.a},props:{form:{type:Object,default:function(){}}},computed:B(B({},Object(R.c)({errorMessage:"access/getError"})),{},{disabledForm:function(){return 0===(this.form.username+this.form.password).length}})}),F=Object(x.a)(E,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("HeightExpander",[n("form",{attrs:{"data-cy":"manual"}},[n("InputField",{attrs:{"data-cy":"username",name:"username",placeholder:e.$t("username.placeholder"),"inset-label":!0},model:{value:e.form.username,callback:function(t){e.$set(e.form,"username",t)},expression:"form.username"}},[e._v("\n      "+e._s(e.$t("username.nameEmail"))+"\n    ")]),e._v(" "),n("InputField",{staticClass:"mb-4",attrs:{"data-cy":"password",type:"password",name:"password",placeholder:e.$t("password.placeholder"),"inset-label":!0},model:{value:e.form.password,callback:function(t){e.$set(e.form,"password",t)},expression:"form.password"}},[e._v("\n      "+e._s(e.$t("password.name"))+"\n    ")]),e._v(" "),n("div",{staticClass:"mb-4 pl-3 text-sm font-light cursor-pointer hover:underline",on:{click:function(t){return e.$emit("forgottenPassword")}}},[e._v("\n      "+e._s(e.$t("passwordForgotten"))+"\n    ")]),e._v(" "),n("div",{staticClass:"flex justify-end"},[n("GeneralButton",{staticClass:"w-full",attrs:{"data-cy":"trigger-login","is-disabled":e.disabledForm,size:"p-4"},nativeOn:{click:function(t){return e.$emit("login")}}},[e._v("\n        "+e._s(e.$t("login"))+"\n      ")])],1),e._v(" "),n("FormErrorHandler",{staticClass:"mt-4",attrs:{error:e.errorMessage,"data-cy":"formerror"}})],1)])}),[],!1,null,null,null).exports,A=n(912),N=Object(r.b)({name:"LoginBoxForgottenPassword",components:{GeneralButton:O.a,InputField:h.a,HeightExpander:f.a},props:{passwordForgotten:{type:Boolean,default:!1}},data:function(){return{email:"",passwordReseted:!1,error:""}},computed:{checkEmail:function(){return this.email?this.email.length>3&&/^(([^<>()[\]\\.,;:\s@"]+(\.[^<>()[\]\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/.test(this.email):null}},watch:{email:function(){0===this.email.length&&(this.error="")}},methods:{close:function(){this.email="",this.error="",this.passwordReseted=!1,this.$emit("closeForgottenPassword")},resetPassword:function(){var e=this;return Object(c.a)(regeneratorRuntime.mark((function t(){var n;return regeneratorRuntime.wrap((function(t){for(;;)switch(t.prev=t.next){case 0:return t.prev=0,t.next=3,e.$apiClient.connect({noLogin:!0,axios:m.a});case 3:return t.next=5,e.$apiClient.getRepository("user");case 5:return n=t.sent,t.next=8,n.requestPasswordReset("koality",{email:e.email});case 8:e.passwordReseted=!0,t.next=15;break;case 11:t.prev=11,t.t0=t.catch(0),e.error=t.t0.message,console.error(t.t0);case 15:case"end":return t.stop()}}),t,null,[[0,11]])})))()}}}),I=Object(x.a)(N,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("HeightExpander",[e.passwordForgotten?n("div",[e.passwordReseted?[n("p",{staticClass:"mb-4 text-sm"},[e._v("\n        "+e._s(e.$t("PasswordResetInitSentence"))+"\n      ")]),e._v(" "),n("GeneralButton",{attrs:{size:"p-3"},nativeOn:{click:function(t){return e.close.apply(null,arguments)}}},[e._v("\n        "+e._s(e.$t("backToLogin"))+"\n      ")])]:[n("h2",{staticClass:"mb-1 font-medium text-lg"},[e._v("\n        "+e._s(e.$t("passwordForgotten"))+"\n      ")]),e._v(" "),n("p",{staticClass:"mb-4 text-sm"},[e._v("\n        "+e._s(e.$t("PasswordForgottenSentence"))+"\n      ")]),e._v(" "),n("InputField",{attrs:{name:"email",error:e.email&&!e.checkEmail?"Das Format der Email Adresse ist nicht korrekt":"","inset-label":!0,required:!0},model:{value:e.email,callback:function(t){e.email=t},expression:"email"}},[e._v("\n        "+e._s(e.$t("email"))+"\n      ")]),e._v(" "),e.error?n("div",{staticClass:"text-red-500 text-sm p-1"},[e._v("\n        "+e._s(e.error)+"\n      ")]):e._e(),e._v(" "),n("div",{staticClass:"flex justify-between items-center mt-6"},[n("GeneralButton",{attrs:{"color-palette":"",size:"py-2 px-3"},nativeOn:{click:function(t){return e.close.apply(null,arguments)}}},[e._v("\n          "+e._s(e.$t("cancel"))+"\n        ")]),e._v(" "),n("GeneralButton",{attrs:{"is-disabled":!e.checkEmail,size:"py-2 px-3"},nativeOn:{click:function(t){return e.resetPassword.apply(null,arguments)}}},[e._v("\n          "+e._s(e.$t("Submit"))+"\n        ")])],1)]],2):e._e()])}),[],!1,null,null,null),D=I.exports,H=n(136),M={};M.props={storybook:{type:Boolean,default:!1},registerActive:{type:Boolean,default:!1},initDemo:{type:Boolean,default:!1}},M.setup=function(e,t){var n=e,o=Object(r.r)(),l=Object(H.c)(),d=l.username,m=l.password,f=(Object(r.i)(!1),Object(r.i)(!1)),h=Object(r.i)(!1),form=Object(r.h)({username:d,password:m}),v=Object(w.f)(),_=function(){var e=Object(c.a)(regeneratorRuntime.mark((function e(){var t,r,l=arguments;return regeneratorRuntime.wrap((function(e){for(;;)switch(e.prev=e.next){case 0:if(t=l.length>0&&void 0!==l[0]&&l[0],!n.storybook){e.next=3;break}return e.abrupt("return");case 3:return r={username:v.demoCredentials[0],password:v.demoCredentials[1]},e.prev=4,o.dispatch("access/resetError"),e.next=8,o.dispatch("access/loginUser",t?r:form);case 8:f.value=!0,e.next=13;break;case 11:e.prev=11,e.t0=e.catch(4);case 13:case"end":return e.stop()}}),e,null,[[4,11]])})));return function(){return e.apply(this,arguments)}}();return Object(r.s)((function(){return n.initDemo}),(function(){n.initDemo&&_(!0)}),{immediate:!0}),{disabledFeature:w.b,initLogin:f,passwordForgotten:h,form:form,clientConfig:v,login:_}},M.components=Object.assign({HeightExpander:f.a,LoginBoxManualLogin:F,SSOLoginButton:y,StartRoute:A.a,LoginBoxForgottenPassword:D},M.components);var T=M,z=Object(x.a)(T,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("HeightExpander",[e.registerActive?e._e():n("div",[e.passwordForgotten?e._e():[n("div",{staticClass:"mb-2 text-center font-light flex items-center justify-center text-sm"},[e._v("\n        "+e._s(e.$t("loginAs"))+"\n      ")]),e._v(" "),e.clientConfig.login.includes("default")?n("LoginBoxManualLogin",{attrs:{form:e.form},on:{login:e.login,forgottenPassword:function(t){e.passwordForgotten=!0}}}):e._e(),e._v(" "),n("div",[e.clientConfig.login.includes("google")||e.clientConfig.login.includes("haendlerbund")?n("div",{staticClass:"py-3 flex justify-center text-sm"},[e._v("\n          "+e._s(e.$t("or"))+"\n        ")]):e._e(),e._v(" "),e.clientConfig.login.includes("google")?n("SSOLoginButton",{staticClass:"mb-4",attrs:{"login-with":"google"}}):e._e(),e._v(" "),e.clientConfig.login.includes("haendlerbund")?n("SSOLoginButton",{staticClass:"mb-4",attrs:{"login-with":"hb"}}):e._e()],1),e._v(" "),e.disabledFeature("loginBox:login:createNewAccount")?e._e():n("div",{staticClass:"text-center mt-6 mb-1 font-light border-t border-gray-300 pt-4 text-sm"},[n("span",[e._v(e._s(e.$t("youHaveNoAccount")))]),e._v(" "),n("span",{staticClass:"cursor-pointer font-medium hover:underline",attrs:{"data-cy":"triggerRegister"},on:{click:function(t){return e.$emit("registerUser")}}},[e._v("\n          "+e._s(e.$t("createNowAccount"))+"\n        ")])]),e._v(" "),e.initLogin?n("StartRoute"):e._e()],e._v(" "),n("LoginBoxForgottenPassword",{attrs:{"password-forgotten":e.passwordForgotten},on:{closeForgottenPassword:function(t){e.passwordForgotten=!1}}})],2)])}),[],!1,null,null,null).exports,W=Object(r.b)({name:"LoginBoxNewPass",components:{GeneralButton:O.a,InputField:h.a,HeightExpander:f.a},data:function(){return{passwordChanged:!1,error:!1,password:"",passwordConfirm:""}},computed:{passwordConfirmLengthCheck:function(){return this.passwordConfirm.length>3&&this.passwordConfirm.length<=300},passwordLengthCheck:function(){return this.password.length>3&&this.password.length<=300},checkPassword:function(){return!!(this.passwordConfirm.length>0&&this.password.length)&&this.passwordConfirm!==this.password},storeAble:function(){return!!(this.passwordConfirm.length&&this.passwordConfirmLengthCheck&&this.password.length&&this.passwordLengthCheck)&&!this.checkPassword}},methods:{close:function(){this.passwordChanged=!1,this.password="",this.passwordConfirm="",this.$router.push(this.$route.path),this.$emit("newPasswordClose")},storeNewPassword:function(){var e=this;return Object(c.a)(regeneratorRuntime.mark((function t(){var n,r,o;return regeneratorRuntime.wrap((function(t){for(;;)switch(t.prev=t.next){case 0:if(e.storeAble){t.next=2;break}return t.abrupt("return");case 2:return n=window.localStorage.getItem("actionToken"),window.localStorage.removeItem("actionToken"),r=e.$route.query.userId,t.prev=5,t.next=8,e.$apiClient.connect({accessToken:n,axios:m.a});case 8:return t.next=10,e.$apiClient.getRepository("user");case 10:return o=t.sent,t.next=13,o.resetPassword("koality",r,{password:e.passwordConfirm});case 13:e.passwordChanged=!0,t.next=21;break;case 16:t.prev=16,t.t0=t.catch(5),e.error=t.t0.message,console.error(t.t0),e.$sentry.captureException(t.t0);case 21:case"end":return t.stop()}}),t,null,[[5,16]])})))()}}}),G=Object(x.a)(W,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("HeightExpander",[n("div",[e.passwordChanged?[n("h2",{staticClass:"mb-1 font-medium text-lg"},[e._v("\n        "+e._s(e.$t("PasswordChanged"))+"\n      ")]),e._v(" "),n("p",{staticClass:"mb-4 text-sm"},[e._v("\n        "+e._s(e.$t("PasswordIsChangedSentence"))+"\n      ")]),e._v(" "),n("GeneralButton",{attrs:{size:"p-3"},nativeOn:{click:function(t){return e.close.apply(null,arguments)}}},[e._v("\n        "+e._s(e.$t("backToLogin"))+"\n      ")])]:[n("h2",{staticClass:"mb-1 font-medium text-lg"},[e._v("\n        "+e._s(e.$t("ChangePassword"))+"\n      ")]),e._v(" "),n("p",{staticClass:"mb-4 text-sm"},[e._v("\n        "+e._s(e.$t("ChangePasswordSentence"))+"\n      ")]),e._v(" "),n("InputField",{attrs:{name:"password",type:"password","inset-label":!0,required:!0,debouncer:!0,error:e.password&&!e.passwordLengthCheck?e.$t("PasswordLengthError"):""},model:{value:e.password,callback:function(t){e.password=t},expression:"password"}},[e._v("\n        "+e._s(e.$t("password.name"))+"\n      ")]),e._v(" "),n("InputField",{attrs:{name:"passwordConfirm",type:"password","inset-label":!0,required:!0,debouncer:!0,error:e.passwordConfirm&&!e.passwordConfirmLengthCheck?e.$t("PasswordLengthError"):""},model:{value:e.passwordConfirm,callback:function(t){e.passwordConfirm=t},expression:"passwordConfirm"}},[e._v("\n        "+e._s(e.$t("password.nameConfirm"))+"\n      ")]),e._v(" "),e.checkPassword?n("div",{staticClass:"text-red-500 text-sm p-1"},[e._v("\n        "+e._s(e.$t("PasswordWontConfirm"))+"\n      ")]):e._e(),e._v(" "),n("div",{staticClass:"flex justify-between items-center mt-6"},[n("GeneralButton",{attrs:{"color-palette":"grayed"},nativeOn:{click:function(t){return e.close.apply(null,arguments)}}},[e._v("\n          "+e._s(e.$t("cancel"))+"\n        ")]),e._v(" "),n("GeneralButton",{attrs:{"is-disabled":!e.storeAble},nativeOn:{click:function(t){return e.storeNewPassword.apply(null,arguments)}}},[e._v("\n          "+e._s(e.$t("StoreNewPassword"))+"\n        ")])],1)]],2)])}),[],!1,null,null,null),U=G.exports,Z={};Z.props={storybook:{type:Boolean,default:!1}},Z.setup=function(e,t){var n=Object(r.r)(),o=Object(r.o)(),l=Object(r.p)();n.dispatch("socket/clearSocket");var c=Object(r.i)(!1),d=Object(r.i)(!1),m=Object(r.i)(!1),f=Object(r.i)(!1),h=Object(r.i)(!1),v=o.value.query,_={demo:function(){c.value=!0},register:function(){d.value=!0,m.value=!1,f.value=!1,h.value=!1},password:function(){d.value=!1,m.value=!0,f.value=!1,h.value=!1},passwordReset:function(){d.value=!1,m.value=!1,f.value=!0,h.value=!1},newPasswordClose:function(){d.value=!1,m.value=!1,f.value=!1,h.value=!1}};Object(r.f)((function(){var e,t,n=Object(w.f)().localStorageKey,r=localStorage.getItem(n);if(r){var c=JSON.parse(r);if(null===(t=null===(e=null==c?void 0:c.access)||void 0===e?void 0:e.user)||void 0===t?void 0:t.wakeUpToken){var d=o.value.query;l.push({path:"/dashboard",query:d})}}!function(e){Object.keys(_).forEach((function(t){Object.keys(e).includes(t)&&_[t]()}))}(v)}));return{getApplicationPath:w.e,initDemo:c,register:d,passwordReset:f,isRegisteredLayout:h,registerUser:function(){Object(w.b)("loginBox:registerUser")||_.register()},passwordForgotten:function(){Object(w.b)("loginBox:passwordForgotten")||_.password()},newPasswordClose:function(){_.newPasswordClose()},isRegistered:function(){h.value=!0}}},Z.components=Object.assign({Card:o.a,LoginBoxLogin:z,LoginBoxRegister:C,LoginBoxNewPass:U,AppMetaLinks:l.a},Z.components);var J=Z,V=(n(1007),Object(x.a)(J,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("div",{staticClass:"flex items-center flex-col",attrs:{"data-cy":"element"}},[n("Card",{directives:[{name:"show",rawName:"v-show",value:!e.initDemo,expression:"!initDemo"}],staticClass:"loginWrapper bg-white p-4 overflow-hidden",class:[{"loginWrapper--register":e.register&&!e.isRegisteredLayout},{"loginWrapper--isRegistered":e.isRegisteredLayout}],attrs:{"data-cy":"wrapper"}},[e.isRegisteredLayout?e._e():n("div",{staticClass:"mb-5 py-3 bg-login-topBackground -mx-5 -mt-5"},[n("h1",{staticClass:"p-2"},[n("img",{class:[e.register?"w-48 pl-4":"w-2/3 mx-auto"],attrs:{src:e.getApplicationPath()+"/images/bigLogo.svg",alt:"logo"}})])]),e._v(" "),e.passwordReset?e._e():n("LoginBoxLogin",{attrs:{"register-active":e.register,storybook:e.storybook,"init-demo":e.initDemo},on:{registerUser:e.registerUser,passwordForgotten:e.passwordForgotten}}),e._v(" "),e.register?n("LoginBoxRegister",{on:{cancelRegister:function(t){e.register=!1},isRegistered:e.isRegistered}}):e._e(),e._v(" "),e.passwordReset?n("LoginBoxNewPass",{on:{newPasswordClose:e.newPasswordClose}}):e._e()],1),e._v(" "),e.initDemo?e._e():n("AppMetaLinks",{staticClass:"mt-4",attrs:{"data-cy":"meta"}})],1)}),[],!1,null,null,null));t.a=V.exports},1075:function(e,t,n){"use strict";n.r(t);var r=n(924).a,o=n(4),component=Object(o.a)(r,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("div",{staticClass:"px-5 w-full"},[e.showLoginBox?n("LoginBox"):e._e()],1)}),[],!1,null,null,null);t.default=component.exports},885:function(e,t,n){e.exports={}},901:function(e,t,n){"use strict";n(885)},911:function(e,t,n){"use strict";n(32),n(98);var r=n(1),o=Object(r.b)({name:"SoftNavigation",props:{name:{type:String,required:!0},separator:{type:String,default:"pipe"},links:{type:Array,default:function(){return[]}},exact:{type:Boolean,default:!1},linkStyle:{type:String,default:"hover:underline cursor-pointer"},noLinkStyle:{type:String,default:""}},setup:function(){var e=Object(r.l)().i18n;return{linkTag:function(path){return path&&0!==path.length?path.match(/^(http|mailto|tel)/)?"a":"nuxt-link":"span"},setLabel:function(label){return e&&e.te(label)?e.t(label):label}}}}),l=(n(901),n(4)),component=Object(l.a)(o,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("nav",{staticClass:"flex flex-wrap",attrs:{role:"navigation"}},e._l(e.links,(function(link,i){return n("div",{key:e.name+"-"+i,staticClass:"flex",class:"separator-"+e.separator},[n(e.linkTag(link.path),{tag:"component",class:[link.path&&e.linkStyle,!link.path&&e.noLinkStyle],attrs:{to:"nuxt-link"===e.linkTag(link.path)?link.path:null,href:"a"===e.linkTag(link.path)?link.path:null,target:"a"===e.linkTag(link.path)?"_blank":null,exact:"nuxt-link"===e.linkTag(link.path)?e.exact:null}},[e._v("\n      "+e._s(e.setLabel(link.label))+"\n    ")])],1)})),0)}),[],!1,null,null,null);t.a=component.exports},912:function(e,t,n){"use strict";n(17),n(16),n(15),n(27),n(19),n(28);var r=n(11),o=n(36),l=n(82),c=n(125),d=n(124);function m(object,e){var t=Object.keys(object);if(Object.getOwnPropertySymbols){var n=Object.getOwnPropertySymbols(object);e&&(n=n.filter((function(e){return Object.getOwnPropertyDescriptor(object,e).enumerable}))),t.push.apply(t,n)}return t}function f(e){for(var i=1;i<arguments.length;i++){var source=null!=arguments[i]?arguments[i]:{};i%2?m(Object(source),!0).forEach((function(t){Object(r.a)(e,t,source[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(source)):m(Object(source)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(source,t))}))}return e}var h={name:"StartRoute",data:function(){return{initRoute:!1,project:null}},computed:f(f({},Object(o.c)({onboarding:"onboarding/getOnboarding",projectPolling:"projects/getPolling",onboardingPolling:"onboarding/getPolling",navAliases:"navigation/getNavAliases"})),{},{combinePolling:function(){return this.projectPolling&&this.onboardingPolling}}),watch:{combinePolling:{handler:function(){this.combinePolling||this.loginRoute()},immediate:!0},onboardingPolling:{handler:function(){!this.onboardingPolling&&this.initRoute&&this.openLoginRoute()},immediate:!0}},methods:{loginRoute:function(){this.initRoute=!1;var e=this.$store.getters["projects/getProjects"][0];if(e){var t=e.id,n=e.systems[0].id;this.$store.dispatch("onboarding/updateOnboarding",t),this.$store.dispatch("projects/setProjectSystem",{pid:t,sid:n}),this.project={pid:t,sid:n},this.initRoute=!0}else this.$router.push({path:this.navAliases.projectsOverview.path})},openLoginRoute:function(){var e=this.project,t=e.pid,n=e.sid,r=Object(d.c)(this.navAliases,"projectsOverview")?this.navAliases.projectsOverview.path:Object(c.b)(this.onboarding.details)?l.a:Object(c.a)(this.onboarding.details).path;this.$router.push(Object(d.d)(r,t,n,this.$route))}},render:function(){return null}},v=n(4),component=Object(v.a)(h,undefined,undefined,!1,null,null,null);t.a=component.exports},915:function(e,t,n){"use strict";var r={name:"Card"},o=n(4),component=Object(o.a)(r,(function(){var e=this,t=e.$createElement;return(e._self._c||t)("div",{staticClass:"w-full p-5 shadow-xl rounded-lg border border-gray-100"},[e._t("default")],2)}),[],!1,null,null,null);t.a=component.exports},916:function(e,t,n){"use strict";n(15);var r=n(7),o=n(911),l=n(21),c=r.default.extend({name:"AppMetaLinks",components:{SoftNavigation:o.a},computed:{metaLinks:function(){var e=Object(l.f)().metaLinks;return[{label:"imprintLabel",path:e.imprint},{label:"privacyLabel",path:e.privacy},{label:"gtcLabel",path:e.gtc}].filter((function(e){return""!==e.path}))}}}),d=n(4),component=Object(d.a)(c,(function(){var e=this,t=e.$createElement;return(e._self._c||t)("SoftNavigation",{staticClass:"justify-center text-gray-600 text-sm",attrs:{links:e.metaLinks,name:"appMeta"}})}),[],!1,null,null,null);t.a=component.exports},924:function(e,t,n){"use strict";(function(e){var r=n(9),o=(n(25),n(35),n(43),n(1)),l=n(189),c=n(1025),d=n(1008),m=n(21),f=n(50),h=n(136),v={name:"PageLogin",layout:"blank",setup:function(t,n){var c=Object(d.a)(),v=c.config,w=c.ssoLoginWithSavedPath,_=c.connectWithSession;Object(f.a)("Selected application config",v);var x=Object(o.r)(),y=Object(o.o)(),O=Object(o.p)(),j=Object(o.l)().i18n,k=Object(l.a)(),C=Object(o.i)(!1),$=Object(m.i)(),R=Object(o.l)(),L=localStorage.getItem("accessoverride");Object(o.i)("true"===e.env.maintananceMode&&!L);return Object(o.f)(Object(r.a)(regeneratorRuntime.mark((function e(){var t,n,r,o,l;return regeneratorRuntime.wrap((function(e){for(;;)switch(e.prev=e.next){case 0:if(t=y.value,n=t.fullPath,"true"===(r=t.query).accessoverride&&localStorage.setItem("accessoverride","true"),x.dispatch("navigation/clearNavPath"),n.includes("lang=en")&&(j.locale="en",j.setLocaleCookie("en")),r.locale&&(j.locale="".concat(r.locale),j.setLocaleCookie("".concat(r.locale))),k.get("locale")&&(o=k.get("locale"),j.locale=o,j.setLocaleCookie(o)),!R.$cpanel){e.next=12;break}return e.next=9,R.$cpanel.login();case 9:return e.sent||O.push({path:"/auth-failure"}),e.abrupt("return");case 12:if("production"!==Object(h.a)()){e.next=23;break}if(!(null==v?void 0:v.useSessionLogin)){e.next=20;break}return e.next=16,_();case 16:!(l=e.sent)&&(null==$?void 0:$.length)?window.location.href=w():l||(C.value=!0),e.next=21;break;case 20:(null==$?void 0:$.length)?window.location.href=w():C.value=!0;case 21:e.next=24;break;case 23:C.value=!0;case 24:case"end":return e.stop()}}),e)})))),{showLoginBox:C}}};v.components=Object.assign({LoginBox:c.a},v.components),t.a=v}).call(this,n(100))},953:function(e,t,n){e.exports={}}}]);