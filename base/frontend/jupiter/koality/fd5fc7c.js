(window.webpackJsonp=window.webpackJsonp||[]).push([[84],{1044:function(e,t,n){"use strict";n.r(t);var r=n(9),o=(n(25),n(912)),c=n(21),l={name:"Auth0Box",components:{StartRoute:o.a},props:{refreshToken:{type:String,default:""},userId:{type:String,default:""}},data:function(){return{initLogin:!1}},created:function(){var e=Object(c.f)().localStorageKey;this.$store.dispatch("projects/clearProjectState"),this.$store.dispatch("access/clearUser"),this.$store.dispatch("socket/clearSocket"),localStorage.getItem(e)&&localStorage.removeItem(e)},mounted:function(){this.login()},methods:{login:function(){var e=this;return Object(r.a)(regeneratorRuntime.mark((function t(){return regeneratorRuntime.wrap((function(t){for(;;)switch(t.prev=t.next){case 0:return t.prev=0,e.errorMessage="",t.next=4,e.$store.dispatch("access/loginUser",{refreshToken:e.refreshToken,userId:e.userId});case 4:e.initLogin=!0,t.next=10;break;case 7:t.prev=7,t.t0=t.catch(0),e.errorMessage=t.t0.response.data.message;case 10:case"end":return t.stop()}}),t,null,[[0,7]])})))()}}},d=n(4),h={name:"PageAuthSuccess",components:{Auth0Box:Object(d.a)(l,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("div",[e.initLogin?n("StartRoute"):e._e()],1)}),[],!1,null,null,null).exports},layout:"blank",data:function(){return{refreshToken:null,userId:null}},mounted:function(){var e=this.$route;this.refreshToken=window.localStorage.getItem("actionToken"),this.userId=e.query.user}},f=Object(d.a)(h,(function(){var e=this,t=e.$createElement,n=e._self._c||t;return n("div",[e.userId?n("Auth0Box",{attrs:{"refresh-token":e.refreshToken,"user-id":e.userId}}):e._e()],1)}),[],!1,null,null,null);t.default=f.exports},912:function(e,t,n){"use strict";n(17),n(16),n(15),n(27),n(19),n(28);var r=n(11),o=n(36),c=n(82),l=n(125),d=n(124);function h(object,e){var t=Object.keys(object);if(Object.getOwnPropertySymbols){var n=Object.getOwnPropertySymbols(object);e&&(n=n.filter((function(e){return Object.getOwnPropertyDescriptor(object,e).enumerable}))),t.push.apply(t,n)}return t}function f(e){for(var i=1;i<arguments.length;i++){var source=null!=arguments[i]?arguments[i]:{};i%2?h(Object(source),!0).forEach((function(t){Object(r.a)(e,t,source[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(source)):h(Object(source)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(source,t))}))}return e}var j={name:"StartRoute",data:function(){return{initRoute:!1,project:null}},computed:f(f({},Object(o.c)({onboarding:"onboarding/getOnboarding",projectPolling:"projects/getPolling",onboardingPolling:"onboarding/getPolling",navAliases:"navigation/getNavAliases"})),{},{combinePolling:function(){return this.projectPolling&&this.onboardingPolling}}),watch:{combinePolling:{handler:function(){this.combinePolling||this.loginRoute()},immediate:!0},onboardingPolling:{handler:function(){!this.onboardingPolling&&this.initRoute&&this.openLoginRoute()},immediate:!0}},methods:{loginRoute:function(){this.initRoute=!1;var e=this.$store.getters["projects/getProjects"][0];if(e){var t=e.id,n=e.systems[0].id;this.$store.dispatch("onboarding/updateOnboarding",t),this.$store.dispatch("projects/setProjectSystem",{pid:t,sid:n}),this.project={pid:t,sid:n},this.initRoute=!0}else this.$router.push({path:this.navAliases.projectsOverview.path})},openLoginRoute:function(){var e=this.project,t=e.pid,n=e.sid,r=Object(d.c)(this.navAliases,"projectsOverview")?this.navAliases.projectsOverview.path:Object(l.b)(this.onboarding.details)?c.a:Object(l.a)(this.onboarding.details).path;this.$router.push(Object(d.d)(r,t,n,this.$route))}},render:function(){return null}},v=n(4),component=Object(v.a)(j,undefined,undefined,!1,null,null,null);t.a=component.exports}}]);