/* global Handlebars:false, DOM:false */

(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;


    var TransferMasterErrorLogProcessor = function(transfer_session_id, sessionUIObj, errorContainer, errorMessage, errorContent) {
        this._sessionUIObj = sessionUIObj;
        this._transfer_session_id = transfer_session_id;
        this._target = errorContainer;
        this._errors = [];
        this._errorMessage = errorMessage;
        this._errorContent = errorContent;
        this._error_message_template = Handlebars.compile(errorMessage.innerHTML);
        this._error_content_template = Handlebars.compile(errorContent.innerHTML);
    };

    YAHOO.lang.augmentObject(TransferMasterErrorLogProcessor.prototype, {
        renderMessage: function(msg) {
            this._errors.push(msg);
            if (DOM.hasClass(this._target, "hidden")) {
                DOM.removeClass(this._target, "hidden");
            }
            this._errorMessage.innerHTML = this._error_message_template({
                error_message: LOCALE.maketext("There [numerate,_1,is,are] [quant,_1,error,errors].", this._errors.length)
            });
            this._errorContent.innerHTML = this._error_content_template({
                errors: this._errors
            });
        },
    });

    window.TransferMasterErrorLogProcessor = TransferMasterErrorLogProcessor;

}(window));
