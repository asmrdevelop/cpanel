(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;
    var LogTail = window.LogTail;

    var TransferLogTail = function(transferSessionId, tail_name, masterErrorProcessorObj) {
        TransferLogTail.superclass.constructor.call(this, "transfers", transferSessionId, tail_name, masterErrorProcessorObj);
    };

    YAHOO.lang.extend(TransferLogTail, LogTail);

    window.TransferLogTail = TransferLogTail;

}(window));
