/* global require: false */

require(["frameworksBuild", "locale!cjtBuild", "app/index.cmb"], function() {
    require(
        [
            "app/index"
        ],
        function(APP) {
            APP();
        }
    );
});
