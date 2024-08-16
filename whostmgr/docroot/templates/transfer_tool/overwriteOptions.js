define(
    [
        "app/overwriteStates",
        "cjt/util/locale",
    ],
    function(OVERWRITE_STATES, LOCALE) {
        "use strict";

        var OVERWRITE_OPTIONS = [
            { label: LOCALE.maketext("Do Not Overwrite"), value: OVERWRITE_STATES.NO_OVERWRITE  },
            { label: LOCALE.maketext("Overwrite"), value: OVERWRITE_STATES.OVERWRITE  },
            { label: LOCALE.maketext("Overwrite with Delete"), value: OVERWRITE_STATES.OVERWRITE_WITH_DELETE  },
        ];

        return OVERWRITE_OPTIONS;
    }
);
