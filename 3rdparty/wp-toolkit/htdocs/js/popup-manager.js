// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

PleskExt.WpToolkit.MakePopoverTitle = function (title) {
    var i = 0;
    var maxStringLength = 54;
    return title.split(' ')
        .reduce(function (rows, word) {
            if ((rows[i].join(' ') + word).length > maxStringLength) {
                i++;
                rows[i] = [word];
            } else {
                rows[i].push(word);
            }

            return rows;
        }, [[]])
        .reduce(function (row, words) {
            return row + (row.length ? '<br/>' : '') + words.join(' ');
        }, '');
};

PleskExt.WpToolkit.escapeAttribute = function(value) {
    return value.toString().escapeHTML().replace(/"/g,'&quot;');
};

PleskExt.WpToolkit.startLongTask = function(event, taskName, action) {
    return Jsw.getComponent('asyncProgressBarWrapper').fly(event.target.cumulativeOffset(), taskName, action);
};

PleskExt.WpToolkit.updatesConfirmation = function(ids, name, locale, onYesClick, requestUrl) {
    Jsw.messageBox.show({
        type: Jsw.messageBox.TYPE_YESNO,
        isAjax: true,
        requestUrl: requestUrl,
        requestParams: {'ids[]': ids},
        subtype: 'toggle',
        text: locale.lmsg('updatesConfirmTitle', {'name': '<b>' + name + '</b>'}),
        onYesClick: onYesClick,
        buttonTitles: {
            yes: locale.lmsg('updatesConfirmYes'),
            no: locale.lmsg('updatesConfirmNo')
        }
    });
};

PleskExt.WpToolkit.snapshotConfirmation = function(title, description, onYesClick, defaultValue, isFullSnapshot) {
    var form = new Jsw.PopupForm({
        singleRowButtons: true
    });

    var locale = Jsw.Locale.getSection('snapshot-confirmation');
    form.setBoxType('form-box');
    form.setTitle(title);
    form.setHint1(description);
    form.setHint((0 == isFullSnapshot ? '<p>' + locale.lmsg('note') + '</p>' : '')
        + '<div class="indent-box">'
        + '<input type="checkbox" id="snapshot" class="checkbox"' + (defaultValue ? ' checked' : '') + '>'
        + '<div class="indent-box-content"><label for="snapshot">' + locale.lmsg('create') + '</label></div>'
        + '</div>');

    form.addRightButton(locale.lmsg('buttonYes'), function(event) {
        form.hide();
        onYesClick(event, {snapshot: $('snapshot').checked});
    }, true, true, {id: 'btn-send'});
    form.addRightButton(locale.lmsg('buttonNo'), function() {form.hide()}, false, false, {id: 'btn-cancel'});
};

PleskExt.WpToolkit.manageThemes = function(ids, name, urls, onHide) {
    new PleskExt.WpToolkit.ManageThemes({
        id: 'manageThemes',
        cls: 'popup-panel popup-panel-wordpress',
        prepareUrl: urls.prepare,
        handlerUrl: urls.handler,
        returnUrl: urls.return,
        urls: urls,
        ids: ids,
        name: name,
        onHide: onHide || function () {}
    });
};


PleskExt.WpToolkit.managePlugins = function(ids, name, urls, onHide) {
    new PleskExt.WpToolkit.ManagePlugins({
        id: 'managePlugins',
        cls: 'popup-panel popup-panel-wordpress',
        prepareUrl: urls.prepare,
        handlerUrl: urls.handler,
        returnUrl: urls.return,
        urls: urls,
        ids: ids,
        name: name,
        onHide: onHide || function () {}
    });
};


PleskExt.WpToolkit.manageSetThemes = function(sets, ids, name, urls, onHide) {
    new PleskExt.WpToolkit.ManageSetThemes({
        id: 'manageSetThemes',
        cls: 'popup-panel popup-panel-wordpress',
        prepareUrl: urls.prepare,
        handlerUrl: urls.handler,
        returnUrl: urls.return,
        urls: urls,
        ids: ids,
        sets: sets,
        name: name,
        onHide: onHide || function () {}
    });
};

PleskExt.WpToolkit.manageSetPlugins = function(sets, ids, name, urls, onHide) {
    new PleskExt.WpToolkit.ManageSetPlugins({
        id: 'manageSetPlugins',
        cls: 'popup-panel popup-panel-wordpress',
        prepareUrl: urls.prepare,
        handlerUrl: urls.handler,
        returnUrl: urls.return,
        urls: urls,
        ids: ids,
        sets: sets,
        name: name,
        onHide: onHide || function () {}
    });
};

PleskExt.WpToolkit.installAsset = function(ids, name, urls, localeKey, ownerGuid, onHide) {
    new PleskExt.WpToolkit.InstallAsset({
        id: 'installAsset',
        cls: 'popup-panel popup-panel-wordpress',
        prepareUrl: urls.availableInstancesUrl,
        handlerUrl: urls.installUrl,
        returnUrl: urls.returnUrl,
        ownerGuid: ownerGuid,
        urls: urls,
        ids: ids,
        localeKey: localeKey,
        name: name,
        onHide: onHide || function () {}
    });
};


PleskExt.WpToolkit.securityScan = function(ids, name, urls) {
    new PleskExt.WpToolkit.CheckInstances({
        id: 'securityScan',
        cls: 'popup-panel popup-panel-wordpress popup-panel-security',
        prepareUrl: urls.prepare,
        handlerUrl: urls.handler,
        urls: urls,
        ids: ids,
        name: name,
        sendButtonId: 'resolveButton',
        cancelButtonId: 'cancelButton'
    });
};

PleskExt.WpToolkit.CommonPopupForm = Class.create(Jsw.ConfirmationPopupManager.PopupForm, {

    _initConfiguration: function($super, config) {
        $super(config);

        this._name = this._getConfigParam('name', '');
        this._urls = this._getConfigParam('urls', {});
        this._returnUrl = this._getConfigParam('returnUrl', null);
    },

    getName: function() {
        return this._name;
    },

    _getUrl: function() {
        return this._urls.dashboard;
    },

    _getBaseUrl: function() {
        return this._urls.base ? this._urls.base : Jsw._baseUrl;
    },

    _setHintToItems: function() {
        this._setInfoHint();
        this._setTogglerHint();
    },

    _setInfoHint: function() {
        $$('span.hint.hint-info').each(function(hintElement) {
            var jsItemTitleElement = hintElement.up('td').down('.jsItemTitle');
            var textContent = jsItemTitleElement.textContent || jsItemTitleElement.innerText;
            new Jsw.DynamicPopupHint.Instance({
                title: PleskExt.WpToolkit.MakePopoverTitle(textContent.escapeHTML()),
                placement: 'right',
                target: hintElement,
                content: hintElement.down('.tooltipData').innerHTML.replace(/\n/, '<br>')
            });
        });
    },

    _setTogglerHint: function() {
        $(this._formListAreaId).select('.toggler').each(function(hintElement) {
            var jsItemTitleElement = hintElement.up('tr').down('.jsItemTitle');
            var textContent = jsItemTitleElement.textContent || jsItemTitleElement.innerText;
            new Jsw.DynamicPopupHint.Instance({
                title: textContent.escapeHTML(),
                placement: 'right',
                target: hintElement,
                content: hintElement.up('td').down('.tooltipData').innerHTML
            });
        });
    },

    _setTitle: function() {
        var title = (1 === this._ids.length)
            ? this.lmsg('titleSingle', {url: this.getName().escapeHTML()})
            : this.lmsg('title', {number: this._ids.length});
        this.setTitle(title);
    },

    _getSendButton: function () {
        return $(this._sendButtonId).firstDescendant() || $(this._sendButtonId);
    },

    _disableSendButton: function() {
        this._getSendButton().disable();
        $(this._sendButtonId).addClassName('disabled');
    },

    _enableSendButton: function() {
        this._getSendButton().enable();
        $(this._sendButtonId).removeClassName('disabled');
    }
});

PleskExt.WpToolkit.Items = Class.create(PleskExt.WpToolkit.CommonPopupForm, {

    _renderPreparePopup: function($super) {
        $super();

        if (this._isSelectRequired()) {
            this._disableSendButton();
        }
    },

    _onSuccessPreparePopup: function(transport) {
        this._clearMessages();
        this._response = typeof transport.responseText === 'string' ? JSON.parse(transport.responseText) : transport;
        if ('success' != this._response.status) {
            if (this._response.redirect) {
                Jsw.redirect(this._response.redirect);
                return;
            }
            this._addErrorMessage(this._response.message.replace(/\n/, '<br>'));
        }

        this.items = this._response.items;

        this._renderTable(this._response.items);
        this._addDropdownMenuObserver();
    },

    _addDropdownMenuObserver: function() {
        $$('.dropdown-toggle').first().observe('click', function() {

            var dropdownMenu = $$('.dropdown-menu').first();
            var popup = $$('.popup-content-area').first();
            var buttonSend = $('btn-send');
            if (!dropdownMenu || !popup || !buttonSend) {
                return false;
            }
            var height = popup.getHeight();
            if (buttonSend.hasClassName('open')) {
                height = height + dropdownMenu.getHeight();
            } else {
                height = height - dropdownMenu.getHeight();
            }
            popup.setStyle({'height': height + 'px'});
            return true;
        });
    },

    _getHeadDescription: function() {
        return '<p id="' + this._formDescriptionId + '-headDescription">' + this.lmsg(this._getHeadDescriptionKey()) + '</p>';
    },

    _getHeadDescriptionKey: function() {
        return 'headDescription'
    },

    _getColumnHeadersHtml: function(totalInstances) {
        return '<th class="first">' + this.lmsg('fieldName') + '</th>' +
            (totalInstances > 1 ? '<th>' + this.lmsg('fieldState') + '</th><th></th>' : '<th>' + this.lmsg('fieldActivate') + '</th>') +
            '<th class="action-icon-set t-r last"></th>';
    },

    _getRowHtml: function(items, totalInstances) {
        return ''
    },

    _addHandlers: function(twoStateControl) {
        if (this._isIntegrationEnabled()) {
            $$('#' + this._contentAreaId + ' .sb-install').first().setAttribute('data-integration-url', this._urls.integration);
        }
    },

    _getInstallUrl: function() {
        if (1 != this._ids.length) {
            // do not use customized URLs or Addendio for mass operations
            return null;
        }
        if (this._urls.integration) {
            return this._urls.integration;
        } else if (this._urls.addendio) {
            return this._urls.addendio;
        }
        return null;
    },

    _getUninstallUrl: function() {
            return this._urls.uninstall;
    },

    _getConfirmRemoveMessageKey: function() {
        return 'confirmUninstall';
    },

    _addUninstallHandlers: function() {
        var context = this;

        $$('a.jsRemoveItem').each(function(link) {
            link.observe('click', function() {
                Jsw.messageBox.show({
                    type: Jsw.messageBox.TYPE_YESNO,
                    buttonTitles: {
                        yes: context.lmsg('removeDialogButtonYes'),
                        no: context.lmsg('removeDialogButtonNo')
                    },
                    text: context.lmsg(context._getConfirmRemoveMessageKey()),
                    subtype: 'delete',
                    onYesClick: function() {
                        context.initialConfig.autoload = false;
                        newContext = new context.constructor(context.initialConfig);
                        params = {
                            'ids[]': context._ids,
                            'item-id': link.readAttribute('data-item-id'),
                            'returnUrl': context._returnUrl
                        };
                        new Ajax.Request(
                            Jsw.prepareUrl(context._getUninstallUrl()),
                            {
                                method: 'post',
                                parameters: params,
                                onSuccess: function() {
                                    newContext.reload();
                                },
                                onException: context._onException.bind(this)
                            }
                        );
                    },
                    onNoClick: function() {
                        context.initialConfig.autoload = true;
                        new context.constructor(context.initialConfig);
                    }
                });
            });
        })
    },

    _getUpdateUrl: function() {
        return '';
    },

    _addUpdateHandlers: function() {
        var context = this;

        $$('a.jsUpdateItem').each(function(link) {
            link.observe('click', function() {
                var onYesClick = function() {
                    Jsw.redirectPost(Jsw.prepareUrl(context._getUpdateUrl()), {
                        'ids': context._ids,
                        'item-id': link.readAttribute('data-item-id'),
                        'returnUrl': context._returnUrl
                    });
                };
                var instanceIds = link.readAttribute('wp-instances').evalJSON();
                var name = (1 == context._ids.length)
                    ? context.lmsg('updatesConfirmNameSingle', {url: context.getName().escapeHTML()})
                    : context.lmsg('updatesConfirmName', {number: instanceIds.length});
                PleskExt.WpToolkit.updatesConfirmation(instanceIds, name, context.getLocale(), onYesClick);
            })
        })
    },

    _addSelectHandlers: function() {
        if (!this._isSelectRequired()) {
            return;
        }

        var context = this;
        var globalCheckbox = $(this._formListAreaId).select('input[name="listGlobalCheckbox"]').first();
        var listCheckbox = $(this._formListAreaId).select('input[name="listCheckbox[]"]');

        listCheckbox.each(function(checkbox) {
            checkbox.observe('click', function() {
                if (checkbox.checked) {
                    context._selectedMarked++;
                } else {
                    context._selectedMarked--;
                    if (globalCheckbox) {
                        globalCheckbox.checked = false;
                    }
                }
                context._toggleSendButton();
            });
        });

        if (globalCheckbox) {
            globalCheckbox.observe('click', function(){
                listCheckbox.each(function(checkbox) {
                    checkbox.checked = globalCheckbox.checked;
                });
                context._selectedMarked = globalCheckbox.checked ? context._ids.length : 0;
                context._toggleSendButton();
            });
        }
    },

    _getCancelButton: function () {
        return $(this._cancelButtonId).down('button') || $(this._cancelButtonId);
    },

    _toggleSendButton: function() {
        if (this._getCancelButton().disabled) {
            return;
        }
        0 == this._selectedMarked ? this._disableSendButton() : this._enableSendButton();
    },

    _preRenderTable: function(items) {
        $(this._formBoxAreaId).update('');
        if (!items.length) {
            $(this._formListAreaId).setStyle({ overflow: 'visible' });
            $(this._formListAreaId).update(this.lmsg('noItems'));
            return;
        }
        $(this._formListAreaId).setStyle({ overflow: 'auto', maxHeight: '350px' });
    },

    _renderTableContent: function(items) {
        var totalInstances = this._ids.length;
        $(this._formListAreaId).update(
            '<table cellspacing="0" width="100%">'
            + '<thead><tr>' + this._getColumnHeadersHtml(totalInstances) +'</tr></thead>'
            + '<tbody id="' + this._formListItemsAreaId + '"></tbody>'
            + '</table>'
        );
        $(this._formListItemsAreaId).update(this._getRowHtml(items, totalInstances));
        this._addHandlers(1 === totalInstances);
        this._addUpdateHandlers();
        this._addUninstallHandlers();
        this._addSelectHandlers();
    },

    _postRenderTable: function(items) {
        this._setHintToItems();

        if (this._isSelectRequired()) {
            this._selectedMarked = 0;
            $(this._formListAreaId).select('input[name="listCheckbox[]"]').each(function(checkbox) {
                if (checkbox.checked) {
                    this._selectedMarked++
                }
            }, this);
            this._toggleSendButton();
        }
    },

    _renderTable: function(items) {
        this._preRenderTable(items);
        this._renderTableContent(items);
        this._postRenderTable(items);
    },

    _getUpdatesInfo: function(totalInstances, item) {
        if (!item._updatesTotal) {
            return '';
        }

        var updatesLabel = (1 === totalInstances) ?
            this.lmsg('updateAvailableSingle', {version: item._updateVersion.escapeHTML()}) :
            this.lmsg('updateAvailable');
        var updatesLink = (1 === totalInstances) ?
            this.lmsg('linkUpdateSingle') :
            this.lmsg('linkUpdate', {number: item._updatesTotal});

        var instanceIds = $A();
        item._instances.each( function(wpInstance) {
            if (wpInstance.hasUpdates) {
                instanceIds.push(wpInstance.id);
            }
        });

        return '<div class="hint-sub hint-attention update-available">' + updatesLabel + '&nbsp;' +
            '<a href="#" class="jsUpdateItem" data-item-id="' + item._id + '" wp-instances="[' + instanceIds + ']">' +
            updatesLink +
            '</a></div>';
    },

    _getEscapedItem: function(item) {
        var escapedItem = {};
        for(var prop in item) {
            if (!item.hasOwnProperty(prop)) {
                continue;
            }
            escapedItem[prop] = String(item[prop]).escapeHTML();
        }

        return escapedItem;
    },

    _getInstancesState: function(item) {
        var activeInstances = 0;
        var tooltipData = '';
        var context = this;

        item._instances.each(function(instance) {
            if (instance.status == 'active') {
                activeInstances++;
            }
            tooltipData += this.lmsg('stateForOneInstance', {
                name: '<a href="' + PleskExt.WpToolkit.escapeAttribute(instance.url) + '" target="_blank">' + instance.name.escapeHTML() + '</a>',
                state: context._getStateText(instance.status == 'active', true)
            }) + '<br>';
        }, this);
        tooltipData = '<span class="tooltipData">' + tooltipData + '</span>';

        var areSameStates = (activeInstances == 0 || activeInstances == item._total);
        var statesCount = '<a href="#" class="toggler">' +
            this.lmsg(areSameStates ? 'sameStatesCount' : 'differentStatesCount', {
                count: activeInstances,
                total: item._total
            }) + '</a>' + tooltipData;

        return this.lmsg('stateForAllInstance', {
            count: statesCount,
            state: this._getStateText(activeInstances != 0, areSameStates)
        })
    },

    _getStateText: function(isActive, isColored) {
        var stateClass = '';
        if (isColored) {
            stateClass = isActive ? "e-checkbox-on" : "e-checkbox-off";
        }
        var stateText = this.lmsg(isActive ? 'stateOn' : 'stateOff');

        return '<span class="' + stateClass + '">' + stateText + '</span>';
    },

    _isSelectRequired: function() {
        return false;
    },

    _isIntegrationEnabled: function() {
        return 1 === this._ids.length && this._urls.integration;
    }
});

PleskExt.WpToolkit.SetItems = Class.create(PleskExt.WpToolkit.Items, {

    _getTitleLocaleKey: function () {
        return '';
    },

    _setTitle: function() {
        this.setTitle(this.lmsg(this._getTitleLocaleKey(), {name: this.getName().escapeHTML()}));
    },

    _initConfiguration: function($super, config) {
        config = Object.extend({
            locale: Jsw.Locale.getSection('manage-sets')
        }, config || {});
        $super(config);
    },

    _getRowHtml: function(items, totalInstances) {
        var rowsHtml = '';
        var oddRow = true;

        items.each(function(item) {
            var itemEscaped = this._getEscapedItem(item);
            rowsHtml +=
                '<tr class="' + (oddRow ? 'odd' : 'even') + '">' +
                    '<td class="first">' +
                        (item.sourceId == 2 ?
                            '<img class="wpt-mgr-3" title="' + this.lmsg(this._getCustomTitle()) + '" src="' + this._getBaseUrl() + 'images/uploaded.png">'
                            :
                            ''
                        ) +
                        '<span class="jsItemTitle">' +
                            itemEscaped.title +
                        '</span> ' +
                            (item.sourceId == 1 ?
                                '<span class="hint hint-info">(?)' +
                                    '<span class="tooltipData">' +
                                        itemEscaped.description +
                                    '</span>' +
                                '</span>'
                                :
                                ''
                            ) +
                    '</td>' +
                    '<td class="action-icon-set t-r last min">' +
                        '<a href="#" class="jsRemoveItem" data-item-id="' + itemEscaped._id + '">' +
                            '<img src="' + this._getBaseUrl() + 'images/delete.svg">' +
                        '</a>' +
                    '</td>' +
                '</tr>'
            ;

            oddRow = !oddRow;
        }, this);

        return rowsHtml;
    },

    _addButtons: function() {
        this.addRightButton(this.lmsg('buttonCancel'), this._onCancelClick, false, false, {id: this._cancelButtonId} );
    },

    _setInfoHint: function() {
        var getItemDataUrl = this._urls.getItemData;
        var waitMessage = this.lmsg('loading');
        $$('span.hint.hint-info').each(function(hintElement) {
            var jsItemTitleElement = hintElement.up('td').down('.jsItemTitle');
            var textContent = jsItemTitleElement.textContent || jsItemTitleElement.innerText;
            var hintItem  = hintElement.up('td').next().down('.jsRemoveItem');
            if (!hintItem) {
                return;
            }

            //this._urls.getItemData +
            new Jsw.DynamicPopupHint.Instance({
                title: PleskExt.WpToolkit.MakePopoverTitle(textContent.escapeHTML()),
                waitMsg: waitMessage,
                url:  getItemDataUrl + '/id/' + hintItem.readAttribute('data-item-id'),
                placement: 'right',
                target: hintElement
            });
        });
    },

    _getBottomDescription: function() {
        return '';
    },

    _getUpdateUrl: function() {
        return '';
    },

    _addDropdownMenuObserver: function() {},

    _getColumnHeadersHtml: function(totalInstances) {
        return '<th class="first">' + this.lmsg('fieldName') + '</th><th class="action-icon-set t-r last"></th>';
    },

    _renderTableContent: function(items) {
        if (items.length == 0) {
            return;
        }
        $(this._formListAreaId).update(
            '<table cellspacing="0" width="100%">'
            + '<thead><tr>' + this._getColumnHeadersHtml(0) +'</tr></thead>'
            + '<tbody id="' + this._formListItemsAreaId + '"></tbody>'
            + '</table>'
        );
        $(this._formListItemsAreaId).update(this._getRowHtml(items, 0));
        this._addUninstallHandlers();
    },

    _postRenderTable: function(items) {
        this._setHintToItems();
    },

    _renderTable: function(items) {
        this._preRenderTable(items);
        this._renderTableContent(items);
        this._postRenderTable(items);
    },

    _getEscapedItem: function(item) {
        var escapedItem = {};
        for(var prop in item) {
            if (!item.hasOwnProperty(prop)) {
                continue;
            }
            escapedItem[prop] = String(item[prop]).escapeHTML();
        }

        return escapedItem;
    },

    _isIntegrationEnabled: function() {
        return false;
    }
});

PleskExt.WpToolkit.InstallAsset = Class.create(PleskExt.WpToolkit.Items, {

    _setTitle: function() {
        this.setTitle(this.lmsg('installPopupTitle', {name: this.getName().escapeHTML()}));
    },

    _getHeadDescriptionKey: function() {
        return 'installPopupHeadDescription'
    },

    _initConfiguration: function($super, config) {
        config = Object.extend({
            locale: Jsw.Locale.getSection(config.localeKey)
        }, config || {});
        $super(config);
        this._ownerGuid = this._getConfigParam('ownerGuid', '');
    },

    _preparePopup: function() {
        var ids = $H();
        var count = 0;

        this._ids.each(function (id) {
            ids.set('ids[' + count + ']', id);
            count++;
        });
        ids.set('ownerGuid', this._ownerGuid);
        new Ajax.Request(
            Jsw.prepareUrl(this._prepareUrl), {
                method: 'post',
                parameters: ids,
                onSuccess: this._onSuccessPreparePopup.bind(this),
                onException: this._onException.bind(this),
            }
        );
    },

    _onSuccessPreparePopup: function(transport) {
        this._clearMessages();
        this._response = typeof transport.responseText === 'string' ? JSON.parse(transport.responseText) : transport;
        if ('success' != this._response.status) {
            if (this._response.redirect) {
                Jsw.redirect(this._response.redirect);
                return;
            }
            this._addErrorMessage(this._response.message.replace(/\n/, '<br>'));
            this._disableInstall();
        }
        this._renderTable(this._response.items);
    },

    _getRowHtml: function(items, totalInstances) {
        var rowsHtml = '';
        var oddRow = true;

        items.each(function(item) {
            var itemEscaped = this._getEscapedItem(item);
            var nameUrl = new Element('a', { href: item.dashboardUrl.escapeHTML(), target: '_blank' }).update(itemEscaped.name).outerHTML;
            var url = new Element('a', { href: item.url.escapeHTML(), target: '_blank' }).update(itemEscaped.url).outerHTML;
            rowsHtml += '<tr class="' + (oddRow ? 'odd' : 'even') + '">' +
                '<td class="select first"><input type="checkbox" class="checkbox" name="listCheckbox[]" id="' + itemEscaped.id + '"></td>' +
                '<td class="first">' +
                '<span class="jsItemTitle">' +
                nameUrl +
                '</span> ' +
                '</td>' +
                '<td class="last nowrap">' + url + '</td>' +
                '</tr>';
            oddRow = !oddRow;
        }, this);

        return rowsHtml;
    },

    _addButtons: function() {
        this.addRightButton(this.lmsg('buttonInstall'), this._onOkClick, true, true, {id: this._sendButtonId} );
        this.addRightButton(this.lmsg('buttonCancel'), this._onCancelClick, false, false, {id: this._cancelButtonId} );
    },

    _getBottomDescription: function() {
        var checkboxId = this._contentAreaId + '-activate';
        var checked = this._getConfigParam('activate', true) ? 'checked="checked"' : '';
        return '<div class="text-center form-row">' +
            '<label for="' + checkboxId + '"><input type="checkbox" id="' + checkboxId + '" ' + checked + '> ' +
            this.lmsg('activateAfterInstall') + '</label>' +
            '</div>';
    },

    _getActivateState: function() {
        return $(this._contentAreaId + '-activate').checked ? 1 : 0;
    },

    _getUpdateUrl: function() {
        return '';
    },

    _getSelectedItems: function() {
        var items = $H();
        $(this._formListAreaId).select('input[name="listCheckbox[]"]').each(function(checkbox) {
            if (checkbox.checked) {
                items.set('items[' + checkbox.id + ']', 1);
            }
        });
        return items;
    },

    _getAdditionalParams: function(params) {
        params.update(this._getSelectedItems());
        params.set('returnUrl', this._returnUrl);
        params.set('ownerGuid', this._ownerGuid);
        params.set('activate', this._getActivateState());
        return params;
    },

    _addDropdownMenuObserver: function() {},

    _getColumnHeadersHtml: function(totalInstances) {
        return '<th class="select first"><input type="checkbox" name="listGlobalCheckbox" class="checkbox"></th>'
            + '<th class="first">'
            + this.lmsg('fieldName')
            + '</th><th class="last">'
            + this.lmsg('fieldUrl')
            + '</th>';
    },

    _renderTableContent: function(items) {
        if (items.length == 0) {
            return;
        }
        $(this._formListAreaId).update(
            '<table cellspacing="0" width="100%">'
            + '<thead><tr>' + this._getColumnHeadersHtml(0) +'</tr></thead>'
            + '<tbody id="' + this._formListItemsAreaId + '"></tbody>'
            + '</table>'
        );
        $(this._formListItemsAreaId).update(this._getRowHtml(items, 0));
        this._addSelectHandlers();
    },

    _setHintToItems: function() {},

    _isSelectRequired: function() {
        return true;
    },

    _postRenderTable: function(items) {
        this._setHintToItems();

        if (this._isSelectRequired()) {
            this._selectedMarked = 0;
            $(this._formListAreaId).select('input[name="listCheckbox[]"]').each(function(checkbox) {
                if (checkbox.checked) {
                    this._selectedMarked++
                }
            }, this);
            this._toggleSendButton();
        }
    },

    _disableInstall: function() {
        $(this._contentAreaId + '-activate').disabled = true;
        this._disableSendButton();
    },

    _renderTable: function(items) {
        this._preRenderTable(items);
        this._renderTableContent(items);
        this._postRenderTable(items);
    },

    _getEscapedItem: function(item) {
        var escapedItem = {};
        for(var prop in item) {
            if (!item.hasOwnProperty(prop)) {
                continue;
            }
            escapedItem[prop] = String(item[prop]).escapeHTML();
        }

        return escapedItem;
    },

    _isIntegrationEnabled: function() {return false;}
});

PleskExt.WpToolkit.ManagePlugins = Class.create(PleskExt.WpToolkit.Items, {

    render: function($super) {
        $super();

        new Jsw.SmallTools({
            renderTo: this._id + '-form',
            renderMode: 'before',
            operations: [{
                componentType: 'Jsw.SmallButton',
                title: this.lmsg('installItem'),
                addCls: 'sb-install',
                handler: this._getInstallItemHandler().bind(this)
            }]
        });
    },

    _initConfiguration: function($super, config) {
        var locale = Jsw.Locale.getSection('controllers.index.manage-plugins');
        config = Object.extend({
            locale: locale,
            longtask: locale.lmsg('taskUpdate')
        }, config || {});
        $super(config);
        this._pluginsStartStates = {};
        this._states = {
            'pre' : {'optionKey' : 'stateDoNotChange', 'textKey' : 'stateDoNotChange'},
            'on' : {'optionKey' : 'stateActivate', 'textKey' : 'stateOn'},
            'off' : {'optionKey' : 'stateDeactivate', 'textKey' : 'stateOff'}
        };
    },

    _getInstallItemHandler: function() {
        var installUrl = this._getInstallUrl();
        if (installUrl) {
            return function() {
                Jsw.redirect(installUrl);
            };
        }
        return function() {
            new PleskExt.WpToolkit.InstallPlugins({
                id: 'installPlugins',
                cls: 'popup-panel popup-panel-wordpress',
                prepareUrl: this._urls.available,
                handlerUrl: this._urls.install,
                ids: this._ids,
                name: this.getName(),
                returnUrl: (this._returnUrl ? this._returnUrl : ''),
                onHide: this._onHide
            });
        }
    },

    _getBottomDescription: function() {
        return (1 === this._ids.length)
            ? this._getUrl() ? ('<a href="' + this._getUrl() + '" target="_blank">' + this.lmsg('managePluginsInsideWordpress') + '</a>') : ''
            : '';
    },

    _getRowHtml: function(items, totalInstances) {
        var rowsHtml = '';
        var oddRow = true;

        items.each(function(plugin) {
            var pluginEscaped = this._getEscapedItem(plugin);
            if (this._ids.length == 1) {
                this._pluginsStartStates[pluginEscaped._id] = ('active' == plugin.status) ? true : false;
            }
            var stateLabel = '<label for="' + pluginEscaped._id + '_active">' + this.lmsg('activeState') + '</label>';
            rowsHtml +=
                '<tr class="' + (oddRow ? 'odd' : 'even') + '">' +
                    '<td class="first">' +
                        (plugin.sourceId == 2 ?
                            '<img class="wpt-mgr-3" title="' + this.lmsg('custom') + '" src="' + this._getBaseUrl() + 'images/uploaded.png">'
                            :
                            ''
                        ) +
                        '<span class="jsItemTitle">' +
                            pluginEscaped.title + ' ' + pluginEscaped.version +
                        '</span> ' +
                        (plugin.sourceId == 2 ?
                            ''
                            :
                            '<span class="hint hint-info">' + this.lmsg('hintInfo') +
                                '<span class="tooltipData">' + pluginEscaped.description + '</span>' +
                            '</span>'
                        ) +
                        this._getUpdatesInfo(totalInstances, plugin) +
                    '</td>' +
                    (totalInstances == 1 ?
                        '<td class="nowrap">' +
                            '<label for="' + pluginEscaped._id + '" class="e-checkbox ' + this._getCheckboxCssClass(totalInstances, pluginEscaped) + '">' +
                                '<input type="checkbox" class="checkbox" id="' + pluginEscaped._id + '" name="' + pluginEscaped._id + '" ' + this._getCheckboxStateAttribute(totalInstances, pluginEscaped) + '> ' +
                                    this._getStateLabels() +
                            '</label>' +
                        '</td>'
                        :
                        '<td class="nowrap">' +
                            this._getInstancesState(plugin) +
                        '</td>' +
                        '<td>' +
                            '<select name="' + pluginEscaped._id + '">' + this._getStateOptions() + '</select>' +
                        '</td>'
                    ) +
                    '<td class="action-icon-set t-r last min">' +
                        '<a href="#" class="jsRemoveItem" data-item-id="' + pluginEscaped._id + '">' +
                            '<img src="' + this._getBaseUrl() + 'images/delete.svg">' +
                        '</a>' +
                    '</td>' +
                '</tr>'
            ;

            oddRow = !oddRow;
        }, this);

        return rowsHtml;
    },

    _getCheckboxCssClass: function(totalInstances, plugin) {
        if (1 === totalInstances) {
            return ('active' == plugin.status) ? 'e-checkbox-on' : 'e-checkbox-off';
        }
        return 'e-checkbox-pre';
    },

    _getCheckboxStateAttribute: function(totalInstances, plugin) {
        return (1 === totalInstances && ('active' === plugin.status)) ? 'checked="checked"' : '';
    },

    _getAdditionalParams: function(params) {
        $(this._formListAreaId).select('.e-checkbox').each(function(label) {
            if (label.hasClassName('e-checkbox-on')) {
                params.set('items[' + label.readAttribute('for') + ']', 1);
            } else if (label.hasClassName('e-checkbox-off')) {
                params.set('items[' + label.readAttribute('for') + ']', 0);
            }
        });
        $(this._formListAreaId).select('select').each(function(select) {
            if (select.getValue() == 'on') {
                params.set('items[' + select.readAttribute('name') + ']', 1);
            } else if (select.getValue() == 'off') {
                params.set('items[' + select.readAttribute('name') + ']', 0);
            }
        });

        params.set('returnUrl', this._returnUrl);

        return params;
    },

    _getStateOptions: function() {
        var options ='';
        for (var option in this._states){
            options += '<option class="e-checkbox-' + option + '" value="' + option + '">'
                + this.lmsg(this._states[option].optionKey) + '</option>'
        }
        return options;
    },

    _getStateLabels: function() {
        var labels ='';
        for (var option in this._states){
            labels += '<span class="e-checkbox-text e-checkbox-text-' + option + '" style="width: 83px;">'
                + this.lmsg(this._states[option].textKey) + '</span>'
        }
        return labels;
    },

    _addHandlers: function($super, twoStateControl) {
        $super(twoStateControl);

        $$('.e-checkbox').each(function(el) {
            var text = [el.down('.e-checkbox-text-off').getWidth(), el.down('.e-checkbox-text-on').getWidth(), el.down('.e-checkbox-text-pre').getWidth()];
            var textMax = text.max();
            var checkboxElement = el.down('.checkbox');

            checkboxElement.observe('click', function(e) {
                var setupElement = function (currentElement, toAdd, toRemove, checked) {
                    currentElement.addClassName('e-checkbox-' + toAdd);
                    currentElement.removeClassName('e-checkbox-' + toRemove);
                    if (typeof checked !== "undefined") {
                        currentElement.down('.checkbox').checked = checked;
                    }
                    currentElement.down('.e-checkbox-text-' + toAdd).setStyle({width: textMax + 'px'});
                };
                if (twoStateControl) { checkboxElement.checked
                        ? setupElement(el, 'on', 'off')
                        : setupElement(el, 'off', 'on');
                } else {
                    if (el.hasClassName('e-checkbox-pre')) {
                        setupElement(el, 'on', 'pre', true);
                     } else if (el.hasClassName('e-checkbox-on')) {
                        setupElement(el, 'off', 'on', false);
                    } else if (el.hasClassName('e-checkbox-off')) {
                        setupElement(el, 'pre', 'off', false);
                    }
                }
            });
        });
    },


    _getUpdateUrl: function() {
        return this._urls.update;
    },

    _needFlyEffect: function() {
        if (this._ids.length > 1) {
            return true;
        }

        var affectedPluginsCount = 0;
        for (var plugin in this._pluginsStartStates) if (this._pluginsStartStates.hasOwnProperty(plugin)) {
            if ($(plugin) && $(plugin).checked != this._pluginsStartStates[plugin]) {
                affectedPluginsCount++;
            }
        }

        return (affectedPluginsCount > 1);
    },

    _getConfirmRemoveMessageKey: function() {
        return 'confirmRemoveItem';
    },
});

PleskExt.WpToolkit.ManageSetPlugins = Class.create(PleskExt.WpToolkit.SetItems, {

    render: function($super) {
        $super();

        new Jsw.SmallTools({
            renderTo: this._id + '-form',
            renderMode: 'before',
            operations: [
                {
                    componentType: 'Jsw.SmallButton',
                    title: this.lmsg('addPlugin'),
                    addCls: 'sb-install',
                    handler: function() {
                        new PleskExt.WpToolkit.AddPluginsToSet({
                            id: 'addPluginsToSet',
                            cls: 'popup-panel popup-panel-wordpress',
                            prepareUrl: this._urls.available,
                            handlerUrl: this._urls.install,
                            ids: this._ids,
                            urls: this._urls,
                            name: this.getName(),
                            returnUrl: (this._returnUrl ? this._returnUrl : ''),
                            onHide: this._onHide
                        });
                    }.bind(this)
                }, {
                    componentType: 'Jsw.bar.Separator'
                }, {
                    componentType: 'Jsw.SmallButton',
                    title: this.lmsg('uploadPlugin'),
                    addCls: 'sb-install',
                    handler: function() {
                        new PleskExt.WpToolkit.UploadSource({
                            sets: this._getConfigParam('sets', []),
                            locale: Jsw.Locale.getSection('controllers.index.manage-plugins'),
                            selectedSetId: this._ids[0],
                            isShowNoneSelectedOption: true,
                            uploadType: 'plugins'
                        });
                    }.bind(this)
                },
            ]
        });
    },

    _getTitleLocaleKey: function () {
        return 'managePluginsTitle';
    },

    _getHeadDescriptionKey: function() {
        return 'headDescriptionSetCurrentPlugins'
    },

    _getConfirmRemoveMessageKey: function() {
        return 'confirmRemovePlugin';
    },

    _getCustomTitle: function() {
        return 'customPlugin';
    },
});

PleskExt.WpToolkit.ManageSetThemes = Class.create(PleskExt.WpToolkit.SetItems, {

    render: function($super) {
        $super();

        new Jsw.SmallTools({
            renderTo: this._id + '-form',
            renderMode: 'before',
            operations: [
                {
                    componentType: 'Jsw.SmallButton',
                    title: this.lmsg('addTheme'),
                    addCls: 'sb-install',
                    handler: function() {
                        new PleskExt.WpToolkit.AddThemesToSet({
                            id: 'addThemesToSet',
                            cls: 'popup-panel popup-panel-wordpress',
                            prepareUrl: this._urls.available,
                            handlerUrl: this._urls.install,
                            ids: this._ids,
                            urls: this._urls,
                            name: this.getName(),
                            returnUrl: (this._returnUrl ? this._returnUrl : ''),
                            onHide: this._onHide
                        });
                    }.bind(this)
                }, {
                    componentType: 'Jsw.bar.Separator'
                }, {
                    componentType: 'Jsw.SmallButton',
                    title: this.lmsg('uploadTheme'),
                    addCls: 'sb-install',
                    handler: function() {
                        new PleskExt.WpToolkit.UploadSource({
                            sets: this._getConfigParam('sets', []),
                            locale: Jsw.Locale.getSection('controllers.index.manage-themes'),
                            selectedSetId: this._ids[0],
                            isShowNoneSelectedOption: true,
                            uploadType: 'themes'
                        });
                    }.bind(this)
                },
            ]
        });
    },

    _getTitleLocaleKey: function () {
        return 'manageThemesTitle';
    },

    _getHeadDescriptionKey: function() {
        return 'headDescriptionSetCurrentThemes'
    },

    _getConfirmRemoveMessageKey: function() {
        return 'confirmRemoveTheme';
    },

    _getCustomTitle: function() {
        return 'customTheme';
    },
});

PleskExt.WpToolkit.ManageThemes = Class.create(PleskExt.WpToolkit.Items, {

    render: function($super) {
        $super();

        new Jsw.SmallTools({
            renderTo: this._id + '-form',
            renderMode: 'before',
            operations: [{
                componentType: 'Jsw.SmallButton',
                title: this.lmsg('installItem'),
                addCls: 'sb-install',
                handler: this._getInstallItemHandler().bind(this)
            }]
        });
    },

    _initConfiguration: function($super, config) {
        var locale = Jsw.Locale.getSection('controllers.index.manage-themes');
        config = Object.extend({
            locale: locale,
            longtask: locale.lmsg('taskUpdate')
        }, config || {});
        $super(config);
    },

    _getInstallItemHandler: function() {
        var installUrl = this._getInstallUrl();
        if (installUrl) {
            return function() {
                Jsw.redirect(installUrl);
            };
        }
        return function() {
            new PleskExt.WpToolkit.InstallThemes({
                id: 'installThemes',
                cls: 'popup-panel popup-panel-wordpress',
                prepareUrl: this._urls.available,
                handlerUrl: this._urls.install,
                ids: this._ids,
                name: this.getName(),
                returnUrl: (this._returnUrl ? this._returnUrl : ''),
                onHide: this._onHide
            });
        }
    },

    _getHeadDescription: function() {
        return '<p id="' + this._formDescriptionId + '-headDescription">' + this.lmsg('headDescription') + '</p>';
    },

    _getBottomDescription: function() {
        if (1 === this._ids.length) {
            return this._getUrl() ? ('<a href="' + this._getUrl() + '" target="_blank">' + this.lmsg('manageThemesInsideWordpress') + '</a>') : '';
        } else {
            return '';
        }
    },

    _getRadioStateAttribute: function(totalInstances, theme) {
        return (1 == totalInstances && ('active' == theme.status)) ? 'checked="checked"' : '';
    },

    _getRowHtml: function(items, totalInstances) {
        var rowsHtml = '';
        var oddRow = true;
        var activeText = this.lmsg(totalInstances > 1 ? 'setActive' : 'active');

        items.each(function(theme) {
            var themeEscaped = this._getEscapedItem(theme);
            rowsHtml +=
                '<tr class="' + (oddRow ? 'odd' : 'even') + '">' +
                    '<td class="first">' +
                        (theme.sourceId == 2 ?
                            '<img class="wpt-mgr-3" title="' + this.lmsg('custom') + '" src="' + this._getBaseUrl() + 'images/uploaded.png">'
                            :
                            ''
                        ) +
                        '<span class="jsItemTitle">' +
                            themeEscaped.title + ' ' + themeEscaped.version +
                        '</span> ' +
                        (theme.sourceId == 2 ?
                            ''
                            :
                            '<span class="hint hint-info" id="hint_' + themeEscaped._id + '">' +
                                this.lmsg('hintInfo') +
                                '<span class="tooltipData">' +
                                    themeEscaped.description +
                                '</span>' +
                            '</span>'
                        ) +
                        this._getUpdatesInfo(totalInstances, theme) +
                    '</td>' +
                    (totalInstances > 1 ?
                        '<td class="nowrap">' +
                            this._getInstancesState(theme) +
                        '</td>'
                        :
                        ''
                    ) +
                    '<td class="nowrap">' +
                        '<label for="' + themeEscaped._id + '">' +
                            '<input class="radio theme-active" type="radio" ' + this._getRadioStateAttribute(totalInstances, themeEscaped) + ' name="themes_active" id="' + themeEscaped._id + '"> ' +
                            activeText +
                        '</label>' +
                    '</td>' +
                    '<td class="action-icon-set t-r last min">' +
                        '<a href="#" class="jsRemoveItem" data-item-id="' + themeEscaped._id + '">' +
                            '<img src="' + this._getBaseUrl() + 'images/delete.svg">' +
                        '</a>' +
                    '</td>' +
                '</tr>'
            ;

            oddRow = !oddRow;
        }, this);
        if (totalInstances > 1) {
            rowsHtml += '<tfoot>' +
                '<tr>' +
                '<td class="first"></td><td></td>' +
                '<td>' +
                '<label for="themes_active"><input class="radio" type="radio" checked="checked" name="themes_active" id="themes_active"> ' + this.lmsg('setDoNotChange') + '</label>' +
                '</td>' +
                '<td class="last min nowrap"></td>' +
                '</tr>' +
                '</tfoot>';
        }

        return rowsHtml;
    },

    _getAdditionalParams: function(params) {
        $(this._formListAreaId).select('.theme-active').each(function(element) {
            if (element.checked) {
                params.set('items[' + element.id + ']', 1);
            }
        });

        params.set('returnUrl', this._returnUrl);

        return params;
    },

    _getUpdateUrl: function() {
        return this._urls.update;
    },

    _needFlyEffect: function() {
        return this._ids.length > 1;
    },

    _getConfirmRemoveMessageKey: function() {
        return 'confirmRemoveItem';
    },
});

PleskExt.WpToolkit.InstallItems = Class.create(PleskExt.WpToolkit.Items, {

    render: function($super) {
        $super();

        var actionBox = new Jsw.SmallTools({
            renderTo: this._id + '-form',
            renderMode: 'before',
            operations: []
        });

        var quickSearchBoxEl = new Element('div', {'class': 'quick-search-box'})
            .update(
                '<span class="search-field"><input type="text" value="" id="popupListSearchTerm"><em><span></span></em></span>'
            )
            .observe('click', function(event) {
                event.stopPropagation();
            });

        actionBox._componentElement.down('.objects-toolbar').insert(quickSearchBoxEl);
        this._addActionBoxHandlers();
        actionBox.addResponsiveButton('search');
    },

    _initConfiguration: function($super, config) {
        $super(config);
        this._selectInstances = this._getConfigParam('selectInstances', false);
    },

    _setTitle: function() {
        if (this._selectInstances) {
            this.setTitle(this.lmsg('installTitleAll'));
        } else if (1 === this._ids.length) {
            this.setTitle(this.lmsg('installTitleSingle', {url: this.getName().escapeHTML()}));
        } else {
            this.setTitle(this.lmsg('installTitle', {number: this._ids.length}));
        }
    },

    _getHeadDescriptionKey: function() {
        return 'installHeadDescription'
    },

    _renderTableContent: function(items) {

        $(this._formListAreaId).update(
            '<table cellspacing="0" width="100%">' +
            '<thead>' +
            '<tr>' +
            '<th class="select first"></th>' +
            '<th class="first">' + this.lmsg('fieldName') + '</th>' +
            '<th>' + this.lmsg('fieldVersion') + '</th>' +
            '<th class="last">' + this.lmsg('fieldRating') + '</th>' +
            '</tr>' +
            '</thead>' +
            '<tbody id="' + this._formListItemsAreaId + '">' +
            '</tbody>' +
            '</table>'
        );

        var rowsHtml = '';
        var oddRow = true;
        items.each(function(item) {

            var itemEscaped = this._getEscapedItem(item);
            var safeTitle = new Element('span');
            safeTitle.innerHTML = item.title.stripTags().escapeHTML();
            var safeDescription = new Element('span');
            safeDescription.innerHTML = item.description.stripTags().escapeHTML();
            rowsHtml += '<tr class="' + (oddRow ? 'odd' : 'even') + '">' +
                '<td class="select first"><input type="checkbox" class="checkbox" name="listCheckbox[]" id="' + itemEscaped.name + '">' +
                '<input type="hidden" id="source-' + itemEscaped.name + '" value="' + item.sourceId + '"></td>' +
                '<td class="first">' +
                '<span class="jsItemTitle">' +
                (safeTitle.textContent || safeTitle.innerText) +
                '</span> ' +
                '<span class="hint hint-info" id="hint_' + itemEscaped.name + '">' + this.lmsg('hintInfo') +
                '<span class="tooltipData">' + (safeDescription.textContent || safeDescription.innerText) + '</span>' +
                '</span>' +
                '</td>' +
                '<td>' + itemEscaped.version + '</td>' +
                '<td class="last min nowrap">' +
                '<div class="star-holder">' +
                '<div class="star-rating" style="width: ' + itemEscaped.rating + '%;"></div>' +
                '</div>' +
                '</td>' +
                '</tr>';

            oddRow = !oddRow;
        }, this);

        $(this._formListItemsAreaId).update(rowsHtml);
        this._addSelectHandlers();
    },

    _addActionBoxHandlers: function() {
        var context = this;
        var originalPrepareUrl = this._prepareUrl;

        var searchHandler = function() {
            context._disableSendButton();

            if ($('popupListSearchTerm').value.length < 2) {
                context.renderTryToSearch();
            } else {
                context._prepareUrl = originalPrepareUrl + '?term=' + encodeURIComponent($('popupListSearchTerm').value);
                context.reload();
            }
        };

        $('popupListSearchTerm').observe('keydown', function(event) {
            if (Jsw.keyCode.ENTER == event.keyCode) {
                event.preventDefault();
                searchHandler();
            }
        });

        $$('#' + this._contentAreaId + ' .search-field em').first().observe('click', searchHandler);
    },

    _renderPreparePopup: function() {
        this._disableSendButton();
        this.renderTryToSearch();
    },

    renderTryToSearch: function() {
        $(this._formBoxAreaId).update('');
        $(this._formListAreaId).setStyle({ overflow: 'visible' });
        $(this._formListAreaId).update(this.lmsg(this._getTryToSearchKey()));
    },

    _getTryToSearchKey: function() {
        return 'tryToSearch';
    },

    _getSelectedItems: function() {
        var items = $H();
        $(this._formListAreaId).select('input[name="listCheckbox[]"]').each(function(checkbox) {
            if (checkbox.checked) {
                var sourceIdElement = $('source-' + checkbox.id);
                var sourceIdValue = sourceIdElement ? sourceIdElement.value : 1;
                items.set('items[' + checkbox.id + ']', sourceIdValue);
            }
        });
        return items;
    },

    _getAdditionalParams: function(params) {
        params.update(this._getSelectedItems());
        params.set('returnUrl', this._returnUrl);
        params.set('activate', this._getActivateState());
        return params;
    },

    _addButtons: function() {
        if (this._selectInstances) {
            var sendButton = this._addSplitButton();
            this._updateSendButtonHandlers(sendButton);
        } else {
            this.addRightButton(this.lmsg('buttonInstall'), this._onOkClick, true, true, {id: this._sendButtonId} );
        }
        this.addRightButton(this.lmsg('buttonCancel'), this._onCancelClick, false, false, {id: this._cancelButtonId} );
    },

    _addSplitButton: function() {
        var selectWpInstances = function() {
            new PleskExt.WpToolkit.SelectWpInstances({
                id: 'selectWpInstances',
                cls: 'popup-panel popup-panel-wordpress',
                prepareUrl: this._urls.selectInstances,
                handlerUrl: this._handlerUrl,
                locale: this.getLocale(),
                ids: this._ids,
                returnUrl: this._returnUrl || '',
                activate: this._getActivateState(),
                items: this._getSelectedItems(),
                urls: this._urls,
                bottomDescriptionHandler: this._getBottomDescription,
                getActivateStateHandler: this._getActivateState,
                longtask: this.lmsg('taskInstall')
            });
        }.bind(this);

        return new Jsw.SplitButton({
            id: this._sendButtonId,
            renderTo: this._rightActionButtonsAreaId,
            title: this.lmsg('buttonInstallAll', {number: this._ids.length}),
            isAction: true,
            isDefault: true,
            onclick: this._onClick.bindAsEventListener(this, this._onOkClick.bind(this)),
            items: [{
                title: this.lmsg('buttonSelectInstances'),
                onclick: this._onClick.bindAsEventListener(this, selectWpInstances)
            }]
        });
    },

    _getCancelButton: function () {
        return $(this._cancelButtonId).down('button') || $(this._cancelButtonId);
    },

    _updateSendButtonHandlers: function(sendButton) {
        this._disableSendButton = function() {
            sendButton.disable();
        };

        this._enableSendButton = function() {
            sendButton.enable();
        };

        this.disable = function() {
            sendButton.disable();
            sendButton.setText('<span class="wait">' + this.lmsg('loading') + '</span>');

            this._getCancelButton().disabled = false;
            $(this._cancelButtonId).addClassName('disabled');
        };

        this.enable = function() {
            sendButton.enable();
            sendButton.setText(this.lmsg('buttonInstallAll', {number: this._ids.length}));

            this._getCancelButton().disabled = false;
            $(this._cancelButtonId).removeClassName('disabled');
        };
    },

    _isSelectRequired: function() {
        return true;
    },

    _getActivateState: function() {
        return 0;
    },

    _needFlyEffect: function() {
        if (this._ids.length > 1) {
            return true;
        }

        return ($(this._formListAreaId).select('input:checkbox[name="listCheckbox[]"]:checked').length > 1);
    }
});

PleskExt.WpToolkit.InstallPlugins = Class.create(PleskExt.WpToolkit.InstallItems, {

    _initConfiguration: function($super, config) {
        var locale = Jsw.Locale.getSection('controllers.index.manage-plugins');
        config = Object.extend({
            locale: locale,
            longtask: locale.lmsg('taskInstall')
        }, config || {});
        $super(config);
        this._pluginsStartStates = {};
    },

    _getBottomDescription: function() {
        var checkboxId = this._contentAreaId + '-activate';
        var checked = this._getConfigParam('activate', true) ? 'checked="checked"' : '';
        return '<div class="text-center">' +
            '<label for="' + checkboxId + '"><input type="checkbox" id="' + checkboxId + '" ' + checked + '> ' + this.lmsg('activateAfterInstall') + '</label>' +
            '</div>';
    },

    _getActivateState: function() {
        return $(this._contentAreaId + '-activate').checked ? 1 : 0;
    }
});

PleskExt.WpToolkit.UploadSource = function(options) {
    var sets = options.sets || [];
    var locale = options.locale;
    var selectedSetId = options.selectedSetId || null;
    var isShowNoneSelectedOption = options.isShowNoneSelectedOption || true;
    var uploadType = options.uploadType || null;
    var instances = options.instances || [];

    var form = new Jsw.PopupForm({
        singleRowButtons: true
    });

    form.setBoxType('form-box');
    form.setTitle(locale.lmsg('uploadTitle'));

    var setSelectOptions = sets.length ? sets.map(function(set) {
        return '<option ' + (selectedSetId == set.id ? ' selected ' : '') + ' value="' + set.id + '"' + '>' +
            set.name.escapeHTML() +
        '</option>';
    }).join() : null;

    var instancesContent = '';

    if (instances.length) {
        var rowsHtml = '';
        var oddRow = true;
        instances.each(function(item) {
            var nameUrl = new Element('a', { href: item.dashboardUrl.escapeHTML(), target: '_blank' }).update(item.name.escapeHTML()).outerHTML;
            var url = new Element('a', { href: item.url.escapeHTML(), target: '_blank' }).update(item.url.escapeHTML()).outerHTML;
            rowsHtml +=
                '<tr class="' + (oddRow ? 'odd' : 'even') + '">' +
                    '<td class="select first">' +
                        '<input type="checkbox" class="checkbox" value="' + item.id + '" name="instances[]" id="' + item.name.escapeHTML() + '">' +
                    '</td>' +
                    '<td>' + nameUrl + '</td>' +
                    '<td class="last nowrap">' + url + '</td>' +
                '</tr>';

            oddRow = !oddRow;
        }, this);

        instancesContent =
            '<div class="form-row">' +
                '<p>' + locale.lmsg('uploadSelectedInstances') + '</p>' +
                '<div id="instancesToUploadList" class="list">' +
                '<table cellspacing="0" width="100%">' +
                    '<thead>' +
                        '<tr>' +
                            '<th class="select first">' +
                                '<input type="checkbox" name="instancesGlobalCheckbox" class="checkbox">' +
                            '</th>' +
                            '<th>' + locale.lmsg('fieldName') + '</th>' +
                            '<th>' + locale.lmsg('fieldUrl') + '</th>' +
                        '</tr>' +
                    '</thead>' +
                    '<tbody>' +
                        rowsHtml +
                    '</tbody>' +
                '</table>' +
                '<span style="" class="field-errors"></span>' +
            '</div>' +
            '<div class="text-center form-row">' +
                '<label for="activateAsset">' +
                    '<input type="checkbox" name="activateAsset"> ' +
                    locale.lmsg('activateAfterInstall') +
                '</label>' +
            '</div>';
    }

    form.setHint(
        '<form id="uploadSourceForm" method="post" enctype="multipart/form-data" action="">' +
            '<div id="fileUploadControl" class="form-row">' +
                '<div class="field-name">' +
                    '<label>' + locale.lmsg('selectLabel') + '</label>' +
                '</div>' +
                '<div class="field-value">' +
                    '<input type="file" name="fileUpload" id="fileUpload" value="" class="f-large-size input-text">' +
                '</div>' +
                '<span style="" id="fileUploadError" class="field-errors"></span>' +
            '</div>' +
            (setSelectOptions ?
            '<p>' + locale.lmsg('selectSetDescription') + '</p>' +
            '<div id="setsControl" class="form-row">' +
                '<div class="field-name">' +
                    '<label>' + locale.lmsg('selectSet') + '</label>' +
                '</div>' +
                '<div class="field-value">' +
                    '<select name="setId">' +
                        (isShowNoneSelectedOption ? '<option value="">' + locale.lmsg('notSelectedSet') + '</option>' : '') +
                        setSelectOptions +
                    '</select>' +
                '</div>' +
                '<span style="" class="field-errors"></span>' +
                (uploadType ? '<input type="hidden" name="uploadType" value="' + uploadType + '" />' : '') +
            '</div>'
            :
            ''
            ) +
            instancesContent +
        '</form>'
    );

    if (instances.length) {
        var globalCheckbox = $('uploadSourceForm').select('input[name="instancesGlobalCheckbox"]').first();
        var listCheckbox = $('uploadSourceForm').select('input[name="instances[]"]');
        listCheckbox.each(function(checkbox) {
            checkbox.observe('click', function() {
                if (!checkbox.checked && globalCheckbox) {
                    globalCheckbox.checked = false;
                }
            });
        });

        if (globalCheckbox) {
            globalCheckbox.observe('click', function(){
                listCheckbox.each(function(checkbox) {
                    checkbox.checked = globalCheckbox.checked;
                });
            });
        }
    }

    var insertError = function (message, element) {
        var errors = $(element).down().next('.field-errors');
        errors.up().addClassName('error');
        errors.update();
        errors.insert({bottom: '<span class="error-hint">' + message + '</span>' });
    };

    var removeError = function (element) {
        var errors = $(element).down().next('.field-errors');
        errors.up().removeClassName('error');
        errors.update();
        errors.insert({bottom: '' });
    };

    form.addRightButton(locale.lmsg('buttonUpload'), function(event) {
        if ('' === $('fileUpload').value) {
            insertError(locale.lmsg('errorEmptyArchive'), 'fileUploadControl');
            return;
        } else {
            removeError('fileUploadControl');
        }

        if ('zip' !== document.forms['uploadSourceForm']['fileUpload'].files[0].name.split('.').pop().toLowerCase()) {
            insertError(locale.lmsg('errorWrongArchiveFormat'), 'fileUploadControl');
            return;
        } else {
            removeError('fileUploadControl');
        }

        if (instances.length && 0 == $('uploadSourceForm').select('input[name="instances[]"]:checked').length) {
            insertError(locale.lmsg('errorNoInstancesSelectedToUpload'), 'instancesToUploadList');
            return;
        } else {
            removeError('fileUploadControl');
        }

        $('uploadSourceForm').submit();
    }, true, true, {id: 'btn-send'});
    form.addRightButton(locale.lmsg('buttonCancel'), function() {form.hide()}, false, false, {id: 'btn-cancel'});
};

PleskExt.WpToolkit.AddAssetsToSet = Class.create(PleskExt.WpToolkit.InstallItems, {

    _initConfiguration: function($super, config) {
        var locale = Jsw.Locale.getSection('manage-sets');
        config = Object.extend({
            locale: locale
        }, config || {});
        $super(config);
    },

    _renderTableContent: function(items) {
        $(this._formListAreaId).update(
            '<table cellspacing="0" width="100%">' +
                '<thead>' +
                    '<tr>' +
                        '<th class="select first"></th>' +
                        '<th class="first">' + this.lmsg('fieldName') + '</th>' +
                        '<th class="last">' + this.lmsg('fieldRating') + '</th>' +
                    '</tr>' +
                '</thead>' +
                '<tbody id="' + this._formListItemsAreaId + '"></tbody>' +
            '</table>'
        );

        var rowsHtml = '';
        var oddRow = false;

        items.each(function(item, key) {
            var checkBoxProperties = item.isAdded ? ' checked disabled ' : '';
            var rowTitle = item.isAdded ? (' title="' + this.lmsg('hasBeenAlreadyAdded') + '" ') : '';
            var itemEscaped = this._getEscapedItem(item);
            var safeTitle = new Element('span');
            safeTitle.innerHTML = item.title.stripTags().escapeHTML();
            oddRow = !oddRow;

            if (item.id) {
                rowsHtml +=
                    '<tr ' + rowTitle + ' class="' + (oddRow ? 'odd' : 'even') + '">' +
                        '<td class="select first">' +
                            '<input type="checkbox" ' + checkBoxProperties + ' class="checkbox" name="listCheckbox[]" value="' + key + '">' +
                        '</td>' +
                        '<td class="first">' +
                            '<img class="wpt-mgr-3" title="' + this.lmsg(this._getCustomTitle()) + '" src="' + this._getBaseUrl() + 'images/uploaded.png">' +
                            '<span class="jsItemTitle">' +
                                (safeTitle.textContent || safeTitle.innerText) +
                            '</span> ' +
                        '</td>' +
                        '<td class="last min nowrap"></td>' +
                    '</tr>'
                ;
                return;
            }

            var safeDescription = new Element('span');
            safeDescription.innerHTML = item.description.stripTags().escapeHTML();
            rowsHtml +=
                '<tr ' + rowTitle + ' class="' + (oddRow ? 'odd' : 'even') + '">' +
                    '<td class="select first">' +
                        '<input type="checkbox" ' + checkBoxProperties + ' class="checkbox" name="listCheckbox[]" value="' + key + '">' +
                    '</td>' +
                    '<td class="first">' +
                        '<span class="jsItemTitle">' +
                            (safeTitle.textContent || safeTitle.innerText) +
                        '</span> ' +
                        '<span class="hint hint-info" id="hint_' + itemEscaped.name + '">' +
                            this.lmsg('hintInfo') +
                            '<span class="tooltipData">' + (safeDescription.textContent || safeDescription.innerText) + '</span>' +
                        '</span>' +
                    '</td>' +
                    '<td class="last min nowrap">' +
                        '<div class="star-holder">' +
                            '<div class="star-rating" style="width: ' + itemEscaped.rating + '%;"></div>' +
                        '</div>' +
                    '</td>' +
                '</tr>'
            ;
        }, this);

        $(this._formListItemsAreaId).update(rowsHtml);
        this._addSelectHandlers();
    },

    _setTitle: function() {
        this.setTitle(this.lmsg(this._getTitleLocaleKey(), {name: this.getName().escapeHTML()}));
    },

    _getTitleLocaleKey: function() {
        return 'titleAddPluginSet';
    },

    _getHeadDescriptionKey: function() {
        return 'hintAddPluginSet'
    },

    _getTryToSearchKey: function() {
        return 'tryToSearchPlugins';
    },

    _needFlyEffect: function() {
        return false;
    },

    _getSelectedItems: function() {
        var items = $H();
        var self = this;
        $(this._formListAreaId).select('input[name="listCheckbox[]"]').each(function(checkbox) {
            if (checkbox.checked && !checkbox.disabled) {
                var item = self.items[checkbox.value];
                items.set('items[' + item.name + '][title]', item.title);
                items.set('items[' + item.name + '][sourceId]', item.sourceId);
                items.set('items[' + item.name + '][name]', item.name);
                items.set('items[' + item.name + '][id]', item.id ? item.id : null);
            }
        });
        return items;
    },

    _getAdditionalParams: function(params) {
        params.update(this._getSelectedItems());
        params.set('returnUrl', this._returnUrl);
        return params;
    },

    _onOkClick: function() {
        var params = $H();
        var count = 0;
        this._ids.each(function(id) {
            params.set('ids[' + count + ']', id);
            count++;
        });
        params = this._getAdditionalParams(params);
        new Ajax.Request(
            this._handlerUrl,
            {
                method: 'post',
                parameters: params,
                onSuccess: this._onInstallSuccess.bind(this)
            }
        );
    },

    _onInstallSuccess: function($super, transport) {
        var response = typeof transport.responseText === 'string' ? JSON.parse(transport.responseText) : transport;
        this._clearMessages();
        if ('info' != response.status) {
            if (response.redirect) {
                Jsw.redirect(response.redirect);
                return;
            }
        } else {
            this._disableSendButton();
            $$('.checkbox').each(function(item){
                if (true == item.checked) {
                    item.up().up().remove();
                }
            });
        }
        this._addStatusMessage(response.status, response.message.replace(/\n/, '<br>'));
    },

    _onCancelClick: function() {
        Jsw.redirect(this._returnUrl);
    },

    _getBottomDescription: function() {
        return '';
    }
});

PleskExt.WpToolkit.AddPluginsToSet = Class.create(PleskExt.WpToolkit.AddAssetsToSet, {

    _getTitleLocaleKey: function() {
        return 'titleAddPluginSet';
    },

    _getHeadDescriptionKey: function() {
        return 'hintAddPluginSet'
    },

    _getTryToSearchKey: function() {
        return 'tryToSearchPlugins';
    },

    _getCustomTitle: function() {
        return 'customPlugin';
    },
});

PleskExt.WpToolkit.AddThemesToSet = Class.create(PleskExt.WpToolkit.AddAssetsToSet, {

    _getTitleLocaleKey: function() {
        return 'titleAddThemeSet';
    },

    _getHeadDescriptionKey: function() {
        return 'hintAddThemeSet'
    },

    _getTryToSearchKey: function() {
        return 'tryToSearchThemes';
    },

    _getCustomTitle: function() {
        return 'customTheme';
    },
});

PleskExt.WpToolkit.InstallThemes = Class.create(PleskExt.WpToolkit.InstallItems, {

    _initConfiguration: function($super, config) {
        var locale = Jsw.Locale.getSection('controllers.index.manage-themes');
        config = Object.extend({
            locale: locale,
            longtask: locale.lmsg('taskInstall')
        }, config || {});
        $super(config);
        this._pluginsStartStates = {};
    },

    _getBottomDescription: function() {
        return '';
    }
});

PleskExt.WpToolkit.SelectWpInstances = Class.create(PleskExt.WpToolkit.Items, {

    _initConfiguration: function($super, config) {
        $super(config);

        this._items = $H(this._getConfigParam('items', {}));
        this._bottomDescriptionHandler = this._getConfigParam('bottomDescriptionHandler', function(){});
        this._getActivateStateHandler = this._getConfigParam('getActivateStateHandler', function(){});
    },

    _setTitle: function() {
        if (1 === this._items.keys().length) {
            this.setTitle(this.lmsg('selectInstancesTitleSingle'));
        } else {
            this.setTitle(this.lmsg('selectInstancesTitle', {number: this._items.keys().length}));
        }
    },

    _getColumnHeadersHtml: function() {
        return '<th class="select first"><input type="checkbox" name="listGlobalCheckbox" class="checkbox" checked></th>' +
            '<th class="first">' + this.lmsg('fieldName') + '</th>' +
            '<th>' + this.lmsg('fieldUrl') + '</th>'
    },

    _getRowHtml: function(items) {
        var rowsHtml = '';
        var oddRow = true;

        items.each(function(item) {
            var itemEscaped = this._getEscapedItem(item);
            var url = new Element('a', { href: item.url.escapeHTML(), target: '_blank' }).update(itemEscaped.url).outerHTML;
            rowsHtml += '<tr class="' + (oddRow ? 'odd' : 'even') + '">' +
                '<td class="select first"><input type="checkbox" class="checkbox" name="listCheckbox[]" value="' + itemEscaped.id + '" checked></td>' +
                '<td><a href="' + this._urls.detail + '/id/' + itemEscaped.id + '">' +  itemEscaped.name + '</a></td>' +
                '<td>' + url + '</td>' +
                '</tr>';

            oddRow = !oddRow;
        }, this);
        return rowsHtml;
    },

    _getHeadDescriptionKey: function() {
        return 'selectInstancesHeadDescription'
    },

    _getBottomDescription: function() {
        return this._bottomDescriptionHandler();
    },

    _addButtons: function() {
        var buttonOk = (1 === this._items.keys().length) ? this.lmsg('buttonInstallOnSelectedSingle')
            : this.lmsg('buttonInstallOnSelected', {number: this._items.keys().length});
        this.addRightButton(buttonOk, this._onOkClick, true, true, {id: this._sendButtonId} );
        this.addRightButton(this.lmsg('buttonCancel'), this._onCancelClick, false, false, {id: this._cancelButtonId} );
    },

    _getAdditionalParams: function(params) {
        var params = $H();
        var count = 0;

        $(this._formListAreaId).select('input[name="listCheckbox[]"]').each(function(checkbox) {
            if (checkbox.checked) {
                params.set('ids[' + count + ']', checkbox.value);
                count++;
            }
        });
        params.set('returnUrl', this._returnUrl);
        params.set('activate', this._getActivateStateHandler());
        params.update(this._items);

        return params;
    },

    _isSelectRequired: function() {
        return true;
    },

    _needFlyEffect: function() {
        if (this._items.keys().length > 1) {
            return true;
        }

        return ($(this._formListAreaId).select('input:checkbox[name="listCheckbox[]"]:checked').length > 1);
    }
});

PleskExt.WpToolkit.CheckInstances = Class.create(PleskExt.WpToolkit.CommonPopupForm, {

    _initConfiguration: function($super, config) {
        config = Object.extend({
            locale: Jsw.Locale.getSection('check')
        }, config || {});
        $super(config);

        this._formListAdditionalCheckersAreaId = this._id + '-form-list-additional-checkers';
        this._reloadOnCancel = false;
        this._backupDescription = '';
    },

    _addButtons: function($super) {
        $super();
        if (this._urls.licenseButton) {
            this.addRightButton(this.lmsg('buttonLicense'), this._onLicenseClick, true, true, {id: 'btn-upgrade'} );
        }
    },

    _onLicenseClick: function() {
        window.open(this._urls.licenseButton, "_blank");
        return false;
    },

    _renderPreparePopup: function($super) {
        $super();
        this._disableSendButton();
    },

    _onCancelClick: function() {
        this.hide();
        var popup = $('wordPressInstancesListPopup');
        if (popup) {
            popup.toggleClassName('collapsed', true);
        }
        if (this._reloadOnCancel) {
            var list = Jsw.getComponent('wordpress-instances-list');
            if (list) {
                list.reload();
            } else if (this._urls.return) {
                Jsw.redirect(this._urls.return);
            }
        }
    },

    _getImageOkUrl: function() {
        return this._getBaseUrl() + '/images/ok.png';
    },

    _updateReloadOnCancel: function(checkResults, cachedResults) {
        for (var wpInstanceId in checkResults) {
            if (cachedResults[wpInstanceId] && checkResults[wpInstanceId] != cachedResults[wpInstanceId]) {
                this._reloadOnCancel = true;
                return;
            }
        }
    },

    _onSuccessPreparePopup: function(transport) {

        this._clearMessages();
        if (!this._urls.licenseButton) {
            this._enableSendButton();
        } else {
            this._disableSendButton();
            this._addStatusMessage('warning', this.lmsg('licenseWarning', {url: this._urls.licenseWarning}));
        }
        try {
            this._response = typeof transport.responseText === 'string' ? JSON.parse(transport.responseText) : transport;
            if ('success' != this._response.status) {
                if (this._response.redirect) {
                    Jsw.redirect(this._response.redirect);
                    return;
                }
                this._addStatusMessage(this._response.status, this._response.message.replace(/\n/, '<br>'));
            }

            if (0 >= this._response.checkers.length) {
                $(this._formBoxAreaId).update('');
                $(this._formListAreaId).update( '<p>' + this.lmsg('checkersNotFound') + '</p>');
                return;
            }

            $(this._formBoxAreaId).update('');
            $(this._formListAreaId).update(
                '<table cellspacing="0" width="100%">' +
                '<tbody id="' + this._formListItemsAreaId + '">' +
                '</tbody>' +
                '</table>' +
                (this._response.hasAdditionalCheckers ? '<br/>' +
                '<p>' + this.lmsg('additionalCheckersDescription') + '</p>' +
                '<table cellspacing="0" width="100%">' +
                '<tbody id="' + this._formListAdditionalCheckersAreaId + '">' +
                '</tbody>' +
                '</table>' : '')
            );

            this._response.checkers.each(function(checker) {
                this._addChecker(checker);
            }, this);
            this._updateReloadOnCancel(this._response.checkResults, this._response.cachedResults);

            if (this._response.backupLink) {
                this._backupDescription = this.lmsg('securityConfirmBackup', {link: this._response.backupLink});
            }

            this._onAllSuccess();

            this._checkChosenCheckers(this);

        } catch (e) {
            this._addErrorMessage(e.message);
            this._addErrorMessage(
                'Internal error: ' + transport.responseText
            );
        }
    },

    _getLoadingIndicatorItems: function(checkers) {
        var items = [];
        $$('.checkers').each(function(row) {
            if (row.checked) {
                items[row.title] = row.title;
            }
        });

        return items;
    },

    _addLoadingIndicator: function(checkers) {
        for (var checker in checkers) {
            if (!checkers.hasOwnProperty(checker)) continue;
            $('checker-image-' + checkers[checker]).src = this._getBaseUrl() + '/images/indicator.gif';
        }
    },

    _addChecker: function(checker) {
        this._itemClass = ('odd' == this._itemClass) ? 'even' : 'odd';

        var image = (0 == checker.unresolved)
            ? '<img id="checker-image-' + checker.id + '" src="' + this._getImageOkUrl() + '" title="">'
            : '<img id="checker-image-' + checker.id + '" src="' + this._getBaseUrl() + '/images/' + (checker.isAdditional ? 'att.png' : 'warning.png') + '" title="' + checker.mainMessage.escapeHTML() + '">';
        var warning = ('' != checker.warningMessage)
            ? '<div class="error-hint hint-sub">' + checker.warningMessage.escapeHTML() + '</div>'
            : '';
        var hint = ('' != checker.hintMessage)
            ? ' <span class="hint hint-info" id="hint_' + checker.id + '">' + this.lmsg('hintInfo') + '<span class="tooltipData">' + checker.hintMessage.stripTags().escapeHTML() + '</span></span>'
            : '';
        var unresolvedText = (1 < this._ids.length && 0 < checker.unresolved)
            ? '<div class="info-hint hint-sub" id="checker-not-secure-item-' + checker.id + '">' + this.lmsg('notSecureOn') + ' ' +
        '<a class="toggler" href="#" id="wordpress-count-item-' + checker.id + '">' +
        this.lmsg('wordPressCount', {count: checker.unresolved}) +
        '</a>' +
        '</div>'
            : '<div class="info-hint hint-sub" id="checker-not-secure-item-' + checker.id + '"></div>';

        var itemHtml = '' +
            '<tr class="' + this._itemClass + '">' +
            '<td>' +
            '<div class="b-indent">' +
            '<span class="b-indent-icon">' +
            image +
            '</span>' +
            '<span class="jsItemTitle">' +
            checker.title.escapeHTML() +
            '</span>' +
            hint +
            warning +
            unresolvedText +
            '</div>' +
            '</td>' +
            '<td class="last t-r">' + this._getCheckerHtml(checker) + '</td>' +
            '</tr>';

        if (checker.isAdditional) {
            $(this._formListAdditionalCheckersAreaId).insert({bottom : itemHtml});
        } else {
            $(this._formListItemsAreaId).insert({bottom : itemHtml});
        }

        this._addCheckChosenCheckersListener(checker);
        this._addWordPressCountCheckerListener(checker);
        this._addRollbackButton(checker);
    },

    _getNotSecuredCheckerHintHtml: function(checker) {
        var unresolvedText = (1 < this._ids.length && 0 < checker.unresolved)
            ? this.lmsg('notSecureOn') + ' ' +
        '<a class="toggler" href="#" id="wordpress-count-item-' + checker.id + '">' +
        this.lmsg('wordPressCount', {count: checker.unresolved}) +
        '</a>'
            : '';
        $('checker-not-secure-item-' + checker.id).update(unresolvedText);
        this._addWordPressCountCheckerListener(checker);
    },

    _addWordPressCountCheckerListener: function(checker)
    {
        var unresolvedCountElement = $('wordpress-count-item-' + checker.id);
        if (unresolvedCountElement) {
            unresolvedCountElement.observe('click',
                this._getUnresolved.bindAsEventListener(this, checker)
            );
        }
    },

    _addCheckChosenCheckersListener: function(checker)
    {
        var checkerElement = $('checker-checkbox-' + checker.id);
        if (checkerElement) {
            checkerElement.observe('change',
                this._checkChosenCheckers.bindAsEventListener(this)
            );
        }
    },

    _checkChosenCheckers: function(event) {
        var checkedCheckersCount = 0;
        $$('.checkers').each(function(row){
            if (row.checked) {
                checkedCheckersCount++;
            }
        });

        if (0 < checkedCheckersCount) {
            $(this._sendButtonId).show();
        } else {
            $(this._sendButtonId).hide();
        }
    },

    _setTogglerHint: function() {

    },

    _getUnresolved: function(event, checker) {
        Event.stop(event);
        var resultElement = $('wordPressInstancesListResult');
        if (resultElement) {
            var instanceId;
            var instancesText = '';
            for (instanceId in checker.unresolvedInstances) {
                var instance = checker.unresolvedInstances[instanceId];
                instancesText += '<tr><td class="nowrap">' +
                    '<a href="' + this._urls.detail + '/id/' + instanceId + '">' + instance.name.escapeHTML() + '</a>' +
                    '</td><td>(' +
                    '<a href="' + PleskExt.WpToolkit.escapeAttribute(instance.url) + '" target="_blank">' + instance.url.escapeHTML() + '</a>)' +
                    '</td></tr>'
            }
            resultElement.update(instancesText);
        }
        var popupElement = $('wordPressInstancesListPopup');
        var topOffset = 0;
        if (popupElement) {
            popupElement.toggleClassName('collapsed', false);
            var currentElement = $('wordpress-count-item-' + checker.id);

            var pos = currentElement.cumulativeOffset();
            var elWidth = popupElement.getWidth();
            var elHeight = popupElement.getHeight();
            var leftPos = (pos[0] - elWidth);
            var topPos = (pos[1]-(elHeight/2)+18);

            var marginTop = parseFloat(popupElement.getStyle('margin-top'));
            var dimensions = document.viewport.getDimensions();
            var viewportOffset = currentElement.getBoundingClientRect();
            var popupBottom = (elHeight/2 + 2*Math.abs(marginTop) + viewportOffset.top);
            var popupTop = popupBottom - elHeight;
            var offset = dimensions.height - popupBottom;

            if (offset < 0) {
                topPos += offset;
                topOffset -= offset;
                if (topPos < 0) {
                    topPos = 0;
                    topOffset -= topPos;
                }
            } else {
                if (topPos < 0) {
                    topOffset = topPos;
                    topPos = 0;
                    if (marginTop < 0 ) {
                        topOffset += marginTop;
                        topPos =  Math.abs(marginTop);
                    }
                } else {
                    if (popupTop < 0) {
                        topPos -= popupTop;
                        topOffset += popupTop;
                    }
                }
            }

            popupElement.removeClassName('collapsed');
            popupElement.setStyle({'left': leftPos + 'px', 'top': topPos + 'px'});
        }

        var arrowElement = $$('.arrow').first();
        if (arrowElement) {
            arrowElement.setStyle({ 'top': '50%'});
            if (topOffset != 0) {
                var topPercent = 50*(elHeight + 2 * topOffset)/(elHeight);
                arrowElement.setStyle({ 'top': topPercent.toFixed(2) + '%'});
            }
        }
    },

    _getCheckerHtml: function(checker) {
        var checked = (checker.chosenByDefault) ? 'checked' : '';
        var checkerHtml = (0 == checker.unresolved)
            ? '<span id="checker-text-' + checker.id + '">' + this.lmsg('ok') + '</span>'
            : '<input class="checkers" type="checkbox" name="checkers[' + checker.id + ']" id="checker-checkbox-' + checker.id + '" ' + checked + ' title="' + checker.id + '">';

        return checkerHtml;
    },

    _onSuccessResponse: function(response) {
        this.enable();

        if (0 >= response.checkers.length) {
            return;
        }

        response.checkers.each(function(checker) {

            if (0 == checker.unresolved) {
                if ($('checker-checkbox-' + checker.id)) {
                    $('checker-checkbox-' + checker.id).up().update(this._getCheckerHtml(checker));
                }
                $('checker-image-' + checker.id).src = this._getImageOkUrl();
                this._addRollbackButton(checker);
                this._getNotSecuredCheckerHintHtml(checker);

            } else {
                if ($('checker-text-' + checker.id)) {
                    $('checker-text-' + checker.id).up().update(this._getCheckerHtml(checker));
                }
                $('checker-image-' + checker.id).src = this._getBaseUrl() + '/images/' + (checker.isAdditional ? 'att.png' : 'warning.png');
                this._getNotSecuredCheckerHintHtml(checker);

            }
            this._addCheckChosenCheckersListener(checker);
            this._onAllSuccess();
        }, this);
        this._updateReloadOnCancel(response.checkResults, response.cachedResults);
    },

    _getHeadDescription: function() {
        return '<p id="' + this._formDescriptionId + '-headDescription">' + this.lmsg('headDescription') + '</p>';
    },

    _getBottomDescription: function() {
        return '<p style="display: none" id="' + this._formDescriptionId + '-bottomDescription"></p>';
    },

    _getAdditionalParams: function(params) {
        $$('.checkers').each(function(row){
            params.set('checkers[' + row.title + ']', row.checked);
        });
        return params;
    },

    _onAllSuccess: function() {
        var bottomDescription = $(this._formDescriptionId + '-bottomDescription');
        if (0 >= $$('.checkers').length) {
            $(this._sendButtonId).hide();
            bottomDescription.writeAttribute('align', 'center');
            bottomDescription.update(this.lmsg('bottomDescription'));
            bottomDescription.show();
        } else {
            $(this._sendButtonId).show();
            bottomDescription.writeAttribute('align', null);
            bottomDescription.update(this._backupDescription);
            this._backupDescription ? bottomDescription.show() : bottomDescription.hide();
        }
        this._checkChosenCheckers(this);
        this._setHintToItems();
    },

    _onException: function($super, transport, exception) {
        $super(transport, exception);
        if (this._urls.licenseButton) {
            this._disableSendButton();
        }
    },

    _onSuccess: function($super, transport) {
        $super(transport);
        if (this._urls.licenseButton) {
            this._disableSendButton();
            this._response.checkers.each(function(checker) {
                $('checker-image-' + checker.id).src = this._getImageOkUrl();
            }, this);
        }
    },

    _onRollbackSubmit: function(event) {
        var rollbackChecker = $(event.target).up('td').down('[data]').readAttribute('data');

        var params = $H();
        var count = 0;
        this._ids.each(function(id) {
            params.set('ids[' + count + ']', id);
            count++;
        });

        params.set('checkers[' + rollbackChecker + ']', true);

        this.disable();
        this._addLoadingIndicator([rollbackChecker]);

        new Ajax.Request(
            this._urls.rollback,
            {
                method: 'post',
                parameters: params,
                onSuccess: this._onSuccess.bind(this),
                onException: this._onException.bind(this)
            }
        );
    },

    _addRollbackButton: function(checker) {
        if (checker.hasRollback && 0 == checker.unresolved) {
            if ($('checker-text-' + checker.id) && $('checker-text-' + checker.id).up().select('[class="btn"]').length > 0) {
                return;
            }
            $('checker-text-' + checker.id).insert({before: this._createButton(this.lmsg('rollback'), this._onRollbackSubmit, false, false, {'data': checker.id})});
        } else if (!checker.hasRollback && 0 < checker.unresolved) {
            $('checker-checkbox-' + checker.id).insert({after: '<div class="hint-sub minor">' + this.lmsg('unableRollback') + '</div> '});
        }
    }
});

PleskExt.WpToolkit.showNewSecurityCheckersNotification = function(params) {
    var locale = Jsw.Locale.getSection('newSecurityCheckersNotification');
    var form = new Jsw.PopupForm({
        id: 'wp-new-security-checkers-notification',
        singleRowButtons: true
    });
    var onHide = function (goToSecurity) {
        new Ajax.Request(
            Jsw.prepareUrl(params.disableNewSecurityCheckersNotificationUrl),
            {
                method: 'post',
                parameters: {
                    goToSecurity: goToSecurity || false
                }
            }
        );
        form.hide();
    };
    form.setBoxType('form-box');
    form.setHint1('<div class="wp-new-security-checkers-notification__image">'
        + '<img src="' + Jsw.prepareUrl(params.imageUrl) + '" class="wp-new-security-checkers-notification__image-inner"/>'
        + '</div>'
    );
    form.setHint(locale.lmsg('description'));
    if (params.isInstancesSecurityManagementAvailable) {
        form.addRightButton(locale.lmsg('buttonYes'), function (event) {
            onHide(true);
            if (typeof params.onSecurityScan === 'function') {
                params.onSecurityScan(event);
            }
        }, true, true, {id: 'btn-send'});
    }
    form.addRightButton(locale.lmsg('buttonNo'), function() {
        onHide();
    }, false, false, {id: 'btn-cancel'});
};
