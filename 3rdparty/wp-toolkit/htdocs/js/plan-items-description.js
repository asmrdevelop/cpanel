// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

Jsw.onReady(Jsw.priority.low, function() {
    var extwptoolkitRow = $('tabs-extrasTab-extras-extwptoolkit-form-row');

    if (!extwptoolkitRow) {
        return;
    }

    var extwptoolkitLabel = extwptoolkitRow.down('label[for="tabs-extrasTab-extras-extwptoolkit"]');

    if (!extwptoolkitLabel) {
        return;
    }

    extwptoolkitLabel.insert('&nbsp;<span class="s-btn sb-help hint-info" id="extwptoolkit-hint">&nbsp;</span>');
    var locale = Jsw.Locale.getSection('extwptoolkitServicePlan');

    new Jsw.DynamicPopupHint.Instance({
        title: locale.lmsg('title'),
        target: 'extwptoolkit-hint',
        placement: 'right',
        content: locale.lmsg('description', {url: locale.lmsg('setUrl')})
    });
});
