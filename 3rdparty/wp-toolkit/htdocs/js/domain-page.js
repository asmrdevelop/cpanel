// Copyright 1999-2019. Plesk International GmbH. All rights reserved.

PleskExt.WpToolkit.addSiteServices = function(urls) {
    var locale = Jsw.Locale.getSection('list.sites.services');

    // update grid layout for adding extra items
    var updateGridLayout = function(element, count) {
        var grid = element.down('.b-grid');
        if (grid.className === 'b-grid') {
            setTimeout(function () {
                var items = grid.getElementsByTagName('li');
                if (!items) {
                    return;
                }
                var itemsLengh = 0;
                for (var i = 0; i < items.length; i++) {
                    items[i].className.split(' ').each(function(className){
                        if (className.match(/b-grid-item-[^\s'"]+/)) {
                            var parts = className.split('b-grid-item-');
                            itemsLengh += parseInt(parts[1]);
                        } else {
                            itemsLengh++;
                        }
                    });
                }
                grid.addClassName('b-grid-' + itemsLengh);
            });
            return;
        }
        grid.className.split(' ').each(function(className){
            if (className.match(/b-grid-[^\s'"]+/)) {
                var parts = className.split('-');
                parts[parts.length - 1] = parseInt(parts[parts.length - 1]) + count;
                grid.addClassName(parts.join('-'));
                grid.removeClassName(className);
            }
        });
    };

    // start WordPress installation on selected domain
    var onClickInstall = function (element) {
        var itemId = getListItem(element).id;
        var domainId = itemId.split(':')[1];
        var buttonWrapper = element.down('.js-wp-install');

        if (buttonWrapper.hasClassName('disabled')) {
            return;
        }

        buttonWrapper.addClassName('disabled');
        buttonWrapper.update('<span class="ajax-loading">' + locale.lmsg('loading') + '</span>');

        Jsw.redirect(urls.install, {
            domain: domainId,
            returnUrl: urls.return + '/id/' + domainId
        });
    };

    // get list item to which this service belongs
    var getListItem = function (element) {
        return element.up('.active-list-item');
    };

    var ce = Jsw.createElement;
    var body = $('content-body');

    // insert quick start block
    var isQuickStartBlockInserted = false;
    var insertQuickStartBlock = function() {
        if (isQuickStartBlockInserted) {
            return;
        }

        body.select('.caption-services-quick-start').each(function(quickStart){
            updateGridLayout(quickStart, 1);

            var newItem = ce('li.b-grid-item',
                ce('.b-grid-item-wrap',
                    ce('.quick-start-block', [
                        ce('.quick-start-name', locale.lmsg('quickStartTitle')),
                        ce('.quick-start-description', locale.lmsg('quickStartDesc')),
                        ce('.quick-start-actions',
                            ce('a.btn', {class: 'js-wp-install', onclick: onClickInstall.bind(this, quickStart)}, locale.lmsg('quickStartAction'))
                        )
                    ])
                )
            );
            Jsw.render(quickStart.down('.b-grid-list'), newItem, 'top');
            isQuickStartBlockInserted = true;
        })
    };

    insertQuickStartBlock();
    if (!isQuickStartBlockInserted) {
        setTimeout(insertQuickStartBlock, 500);
    }

    // insert quick access block (for plesk version >= 18.0 )
    var isQuickAccessBlockInserted = false;
    var insertQuickAccessBlock = function() {
        if (isQuickAccessBlockInserted) {
            return;
        }

        // start WordPress installation on selected domain
        var onClickInstall = function (element) {
            var itemId = getListItem(element).id;
            var domainId = itemId.split(':')[1];

            Jsw.redirect(urls.install, {
                domain: domainId,
                returnUrl: urls.return + '/id/' + domainId,
            });
        };

        body.select('.caption-services').each(function (services) {
            if (getListItem(services).down('.caption-services-apps-ext-WordPress')) {
                // this domain already has installed WordPress instances
                return;
            }

            var toolsList = services.down('.tools-list');
            if (!toolsList) {
                return;
            }

            var newItem = ce('li.tools-item',
                ce('a.tool-block', { href: urls.list, 'data-identity': 'buttonWordPress' },
                    [
                        ce('span.tool-icon',
                            ce('img', { src: urls.base + '/images/wordpresses.png', alt: 'WordPress' })
                        ),
                        ce('span.tool-name', locale.lmsg('serviceName')),
                        ce('div.caption-service-toolbar',
                            ce('div.caption-service-item.item-visible',
                                ce('a', { href: '#', class: 'js-wp-install', onclick: onClickInstall.bind(this, services) }, locale.lmsg('serviceAction'))
                            )
                        ),
                    ]
                )
            );
            Jsw.render(toolsList, newItem, 'bottom');
            isQuickAccessBlockInserted = true;
        });
    };

    insertQuickAccessBlock();
    if (!isQuickAccessBlockInserted) {
        setTimeout(insertQuickAccessBlock, 500);
    }

    // insert service block
    var isServiceBlockInserted = false;
    var insertServiceBlock = function() {
        if (isServiceBlockInserted) {
            return;
        }

        body.select('.caption-services-custom').each(function(services) {
            if (getListItem(services).down('.caption-services-apps-ext-WordPress')) {
                var quickStartBlock = services.parentNode.querySelector('.caption-services-quick-start');
                if (quickStartBlock) {
                    quickStartBlock.remove();
                }
                // this domain already has installed WordPress instances
                return;
            }

            updateGridLayout(services, 2);

            var newItem = ce('li.b-grid-item.b-grid-item-2',
                ce('.b-grid-item-wrap',
                    ce('.caption-service-block', [
                        ce('span.caption-service-title', [
                            ce('i.caption-service-icon', [
                                ce('a', {href: '#'},
                                    ce('img', {src: urls.base + '/images/wordpresses.png'})
                                )
                            ]),
                            ce('span.caption-service-name',
                                ce('a', {href: urls.list}, locale.lmsg('serviceName'))
                            )
                        ]),
                        ce('.caption-service-toolbar',
                            ce('.caption-service-item.item-visible',
                                ce('a.btn', {class: 'js-wp-install', onclick: onClickInstall.bind(this, services)}, locale.lmsg('serviceAction'))
                            )
                        )
                    ])
                )
            );
            Jsw.render(services .down('.b-grid-list'), newItem, 'bottom');
            isServiceBlockInserted = true;
        });
    };

    insertServiceBlock();
    if (!isServiceBlockInserted) {
        setTimeout(insertServiceBlock, 500);
    }
};
