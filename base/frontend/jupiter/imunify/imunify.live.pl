#!/usr/local/cpanel/3rdparty/bin/perl

BEGIN { unshift @INC, '/usr/local/cpanel', '/usr/local/cpanel/whostmgr/cgi/imunify/handlers'; }

use strict;
use warnings;
use locale ':not_characters';   # utf-8
use JSON;

use Cpanel::LiveAPI();
use Cpanel::JSON;
use Data::Dumper;
use CGI;

use Imunify::File;
use Imunify::Render;
use Imunify::Wrapper;
use Imunify::Exception;
use Imunify::Utils;

#use CGI::Carp qw(fatalsToBrowser); # uncomment to debug 500 error

my $panel = Cpanel::LiveAPI->new();

eval {
    my $cgi = CGI->new;
    my $json = $cgi->param('POSTDATA');

    if (!$json) {
        main();
    } else {
        my $request = Cpanel::JSON::Load($json);
        my $command = $request->{'command'} || 'default';
        if ($command eq 'commandIE') {
            Imunify::Wrapper::imunfyEmailRequest($request, 0);
        } else {
            Imunify::Wrapper::request($request, 0);
        }
    }

    $panel->end();
};

if ($@) {
    if (ref($@) && $@->can('asJSON')) {
        $@->asJSON();
    } else {
        die Imunify::Exception->new($@)->asJSON();
    }
}

sub main {
    my $i360ieExist = 0;
    if (-e '/var/run/imunifyemail/quarantine.sock') {
        $i360ieExist = 1;
    }

    my $file_path = "/usr/local/cpanel/base/frontend/jupiter/imunify/assets/static/importmap.json";
    my $path_to_static = "./assets/static/";

    my $json_text = do {
        open(my $json_fh, "<:encoding(UTF-8)", $file_path)
            or die("Can't open \"$file_path\": $!\n");
        local $/;
        <$json_fh>
    };

    my $json = JSON->new;
    my $data = $json->decode($json_text);

    foreach my $key (keys %{$data->{imports}}) {
        if (index($data->{imports}{$key}, "http") != 0) {
            $data->{imports}{$key} = $path_to_static . $data->{imports}{$key};
        }
    }

    my $importmap = encode_json($data);

    print "Content-type: text/html; charset=utf-8\n\n";
    print $panel->header('');

    print qq{<script>var i360role = "client"; var i360userName = "$ENV{REMOTE_USER}"; var i360ieExist = "$i360ieExist"</script>};

    print '
    <meta name="importmap-type" content="systemjs-importmap">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preload" href="./assets/static/shared-dependencies/single-spa.min.js" as="script"/>
    <link rel="preload" href="./assets/static/shared-dependencies/single-spa-layout.min.js" as="script"/>
    ';
    print qq {
    <script type="systemjs-importmap">
        ${importmap}
    </script>
    };
    print '
<script src="./assets/static/systemjs-conflict-patch-pre.js"></script>
<script src="./assets/static/shared-dependencies/system.min.js"></script>
<script src="./assets/static/shared-dependencies/amd.min.js"></script>
<script src="./assets/static/shared-dependencies/named-exports.min.js"></script>
<script src="./assets/static/shared-dependencies/named-register.min.js"></script>
<script src="./assets/static/systemjs-conflict-patch-post.js"></script>
<script src="./assets/static/shared-dependencies/zone.min.js"></script>
<script src="./assets/static/load-scripts-after-zone.js"></script>

<div id="spa_wrapper"><div></div></div>
<template id="single-spa-layout">
    <single-spa-router mode="hash" containerEl="#spa_wrapper">
        <div class="i360-app i360-app-outer i360-client i360-cpanel">
            <application name="@imunify/nav-root"></application>
            <div class="main-content">
                <route path="360/:role/email">
                    <application name="@imunify/email-root" loader="loader"></application>
                </route>
                <route default>
                    <application name="@imunify/other-root" loader="loader"></application>
                </route>
            </div>
        </div>
    </single-spa-router>
</template>
';
    print $panel->footer();
}
