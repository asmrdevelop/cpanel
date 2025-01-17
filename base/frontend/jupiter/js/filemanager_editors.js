String.prototype.normalize_charset = function() {
    return this.toLowerCase().replace(/[_,.-]/, "");
};

function check_for_encoding_change(template, data) {
    var saved_charset = data[0].charset;
    if (saved_charset.normalize_charset() !== CHARSET.normalize_charset()) {
        var message = YAHOO.lang.substitute(
            template, {
                old_charset: CHARSET.toUpperCase(),
                new_charset: saved_charset.toUpperCase(),
            }
        );

        var enc_dialog = new CPANEL.ajax.Common_Dialog("enc_changed", {
            width: "500px",
            show_status: true,
            status_html: LEXICON.reloading,
        });

        enc_dialog.cfg.getProperty("buttons")[0].text = LOCALE.maketext("OK");

        // Omit the cancel button
        enc_dialog.cfg.getProperty("buttons").pop();

        DOM.addClass(enc_dialog.element, "cjt_notice_dialog cjt_info_dialog");

        enc_dialog.setHeader("<div class='lt'></div><span>" + LEXICON.charset_changed + "</span><div class='rt'></div>");

        enc_dialog.renderEvent.subscribe(function() {
            this.form.innerHTML = message;
            this.center();
        });

        enc_dialog.submitEvent.subscribe(function() {

            // so we catch file_charset as well as charset, the_charset, etc.
            var new_url = location.href.replace(/([^&?]*charset)=[^&]*/g, "$1=" + saved_charset);
            location.href = new_url;
        });

        this.fade_to(enc_dialog)[0].onComplete.subscribe(this.hide, this, true);

        return false;
    }
}

function check_file_edits() {
    var result = {
        isFileModified: false,
        changedContent: "",
    };

    if (USE_LEGACY_EDITOR) {
        result.changedContent = editAreaLoader.getValue(editAreaEl);
    } else {
        result.changedContent = ace_editor.getSession().getValue();
    }
    result.isFileModified = ( result.changedContent !== savedContent ) ? true : false;
    return result;
}

function confirm_close(clicked_el) {
    var res = check_file_edits();
    var isFileEdited = res.isFileModified;

    if (isFileEdited) {
        var confirmed = confirm(LEXICON.confirm_close);
        if (!confirmed) {
            return;
        } else {
            window.close();
        }
    }
    window.close();
}
