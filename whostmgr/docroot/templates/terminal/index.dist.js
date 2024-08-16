/* global require: false */

require(["frameworksBuild", "locale!cjtBuild", "app/index.cmb"], function() {
    "use strict";

    require(
        [
            "app/index"
        ],
        function(APP) {
            APP();
        }
    );
});
