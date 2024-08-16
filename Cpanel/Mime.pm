package Cpanel::Mime;

# cpanel - Cpanel/Mime.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Carp                           ();
use Cpanel                         ();
use Cpanel::Config::userdata::Load ();
use Cpanel::Encoder::Tiny          ();
use Cpanel::FileUtils::TouchFile   ();
use Cpanel::HttpUtils::Htaccess    ();
use Cpanel::Logger                 ();
use Cpanel::Locale                 ();
use bytes;    #case 15186

use Cpanel::Parser::Vars ();

use Cpanel::API       ();
use Cpanel::API::Mime ();

our $VERSION = '1.1';

my $logger = Cpanel::Logger->new();

##################################################
## cpdev: MIME

## DEPRECATED
sub api2_listmime {
    ## system, user
    my %CFG = ( @_, 'api.quiet' => 1 );
    if ( $CFG{'system'} eq 'no' ) {
        $CFG{'type'} = 'user';
    }
    elsif ( $CFG{'user'} eq 'no' ) {
        $CFG{'type'} = 'system';
    }
    my $result = Cpanel::API::wrap_deprecated( "Mime", "list_mime", \%CFG );
    ## API/Mime eliminates the abbreviation of 'ext', but legacy usage still expects
    map { $_->{ext} = $_->{extension} } @{ $result->data() };
    return $result->data();
}

## DEPRECATED
sub add_mime {
    my ( $type, $extension ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Mime", "add_mime", { type => $type, extension => $extension } );
    ## returns nothing or empty string; no need to print
    return;
}

## DEPRECATED
sub del_mime {
    my ($type) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Mime", "delete_mime", { type => $type } );
    return;
}

##################################################
## cpdev: HANDLERS

## DEPRECATED
sub api2_listhandlers {
    ## system, user
    my %CFG = ( @_, 'api.quiet' => 1 );
    if ( $CFG{'system'} eq 'no' ) {
        $CFG{'type'} = 'user';
    }
    elsif ( $CFG{'user'} eq 'no' ) {
        $CFG{'type'} = 'system';
    }
    my $result = Cpanel::API::wrap_deprecated( "Mime", "list_handlers", \%CFG );
    ## API/Mime eliminates the abbreviation of 'ext', but legacy usage still expects
    map { $_->{ext} = $_->{extension} } @{ $result->data() };
    return $result->data();
}

## DEPRECATED
sub add_handler {
    my ( $extension, $handler ) = @_;
    my $result = Cpanel::API::wrap_deprecated(
        "Mime", "add_handler",
        { extension => $extension, handler => $handler }
    );
    return;
}

## DEPRECATED
sub del_handler {
    my ($extension) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Mime", "delete_handler", { extension => $extension } );
    return;
}

##################################################
## cpdev: REDIRECTS

## DEPRECATED
sub api2_listredirects {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Mime", "list_redirects", \%CFG );
    return $result->data();
}

# MUST ALWAYS ALLOW LISTING OR FILEMANAGER WILL BREAK
sub listredirects {
    $logger->info( 'Deprecated use of Mime::listredirects, please use the api2 version : ' . $Cpanel::Parser::Vars::file );
    my @REDIRECTS = Cpanel::HttpUtils::Htaccess::getredirects();

    my %RD;
    foreach my $redirect (@REDIRECTS) {
        next if ( $redirect->{'domain'} ne '.*' && $redirect->{'domain'} ne '(.*)' );
        $RD{ $redirect->{'sourceurl'} } = $redirect->{'targeturl'};
        if ( $redirect->{'wildcard'} ) {
            $RD{ $redirect->{'sourceurl'} } .= ( $redirect->{'targeturl'} =~ /\/$/ ? '*' : '/*' );
        }
        $RD{ $redirect->{'sourceurl'} } .= "=" . $redirect->{'type'};
    }
    return %RD;
}

## no known callers
# MUST ALWAYS ALLOW LISTING OR FILEMANAGER WILL BREAK
sub _listredirects {
    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";

    if ( !-e $htaccess ) {
        Cpanel::FileUtils::TouchFile::touchfile($htaccess);
        return;
    }

    if ( open my $htaccess_fh, '<', $htaccess ) {
        my %REDIRECTS;
        while ( my $line = readline $htaccess_fh ) {
            if ( $line =~ m/^redirect(match)?\s+(\S+)\s+(\S+)\s+(\S+)/i ) {
                my $type = $2;
                my $src  = $3;
                my $dest = $4;
                $src =~ s/^\^//g;
                $src =~ s/\$$//g;
                $REDIRECTS{$src} = { 'dest' => $dest, 'type' => $type };
            }
        }
        close $htaccess_fh;
        return %REDIRECTS;
    }
    else {
        $logger->warn("Failed to read $htaccess: $!");
        print "<b>Error while opening $htaccess</b>\n";
        return;
    }
}

## DEPRECATED
## good example of preserving legacy functionality
sub add_redirect {
    ## note: the method signature was changed slightly for clarity
    my ( $src, $type, $url, $domain, $wildcard, $rdwww ) = @_;
    my %args = (
        src               => $src,
        type              => $type,
        redirect          => $url,
        domain            => $domain,
        redirect_wildcard => $wildcard,
        redirect_www      => $rdwww,
        'api.quiet'       => 1,
    );

    ## important note: &add_redirect and &del_redirect are the only two
    ##   functions that are dispatched as 'moduleapi1'; see cpanel.pl
    my $result = Cpanel::API::wrap_deprecated( "Mime", "add_redirect", \%args );

    my $messages_raw = $result->messages() || [];
    my @messages     = map { Cpanel::Encoder::Tiny::safe_html_encode_str($_) } @$messages_raw;
    my $errors_raw   = $result->errors() || [];
    my @errors       = map { Cpanel::Encoder::Tiny::safe_html_encode_str($_) } @$errors_raw;

    return {
        status    => $result->status(),
        statusmsg => join( "<br/>\n", @messages ),
        error     => join( "<br/>\n", @errors ),
    };
}

## DEPRECATED
sub del_redirect {
    my ( $src, $domain, $docroot ) = @_;

    ## important note: &add_redirect and &del_redirect are the only two functions that
    ##   are dispatched as 'moduleapi1'; see cpanel.pl
    my $result = Cpanel::API::wrap_deprecated(
        "Mime", "delete_redirect",
        { domain => $domain, src => $src, docroot => $docroot, 'api.quiet' => 1 }
    );
    my $messages = $result->messages() || [];
    my $errors   = $result->errors()   || [];
    return {
        status    => $result->status(),
        statusmsg => join( "< br/>\n", @$messages ),
        error     => join( "< br/>\n", @$errors ),
    };
}

## DEPRECATED
sub api2_redirecturlname {
    ## url
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Mime", "redirect_info", \%OPTS );
    return [ $result->data() ];
}

## DEPRECATED
sub api2_redirectname {
    ## domain
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Mime", "redirect_info", \%OPTS );
    return [ $result->data() ];
}

##################################################
## cpdev: HOTLINKS

## DEPRECATED: use api2_list_hotlinks instead
sub gethotlinkurls {
    if ( !main::hasfeature("hotlink") ) { return (); }

    my %URLS;
    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";

    if ( !-e $htaccess ) {
        Cpanel::FileUtils::TouchFile::touchfile($htaccess);
    }

    if ( open my $htaccess_fh, "<", "$htaccess" ) {
        while ( my $line = readline $htaccess_fh ) {
            if ( $line =~ /^RewriteCond/i && $line =~ /\%\{HTTP_REFERER\}/ ) {
                my $url;
                ( undef, undef, $url ) = split / /, $line;
                $url =~ s/^\!\^//g;
                $url =~ /(\S+)/;
                $url = $1;
                $url =~ s/\/\.\*\$$//g;
                next if ( $url eq '$' );
                $url =~ s/\$*$//g;
                if ( $url ne "" ) { $URLS{$url} = 1; }
            }
        }
        close $htaccess_fh;
    }
    else {
        print "<b>Error: while opening $htaccess</b>\n";
    }

    unless ( scalar keys %URLS ) {
        delete @URLS{ keys %URLS };
        my $userdata = Cpanel::Config::userdata::Load::load_userdata_main($Cpanel::user);
        foreach my $subdomain ( @{ $userdata->{'sub_domains'} } ) {
            $URLS{ 'http://www.' . $subdomain } = 1;
            $URLS{ 'http://' . $subdomain }     = 1;
        }
        foreach my $parkeddomain ( @{ $userdata->{'parked_domains'} } ) {
            $URLS{ 'http://' . $parkeddomain }     = 1;
            $URLS{ 'http://www.' . $parkeddomain } = 1;
        }

        $URLS{ 'http://' . $Cpanel::CPDATA{'DNS'} }     = 1;
        $URLS{ 'http://www.' . $Cpanel::CPDATA{'DNS'} } = 1;

    }

    foreach my $url ( sort keys %URLS ) {
        print "$url\n";
    }
    return "";
}

## DEPRECATED
sub add_hotlink {
    my ( $urls, $extensions, $rurl, $allownull ) = @_;
    my $result = Cpanel::API::wrap_deprecated(
        "Mime",
        "add_hotlink",
        {
            urls         => $urls, extensions => $extensions, allow_null => $allownull,
            redirect_url => $rurl
        }
    );
    ## returns actual status!
    return $result->status();
}

## DEPRECATED
sub del_hotlink {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Mime", "delete_hotlink" );
    ## returns only false values
    return;
}

## DEPRECATED: use api2_list_hotlinks instead
sub linkallownull {
    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";

    if ( open my $htaccess_fh, "<", $htaccess ) {
        while ( my $line = readline($htaccess_fh) ) {
            $line =~ s/\n//g;
            if ( $line eq 'RewriteCond %{HTTP_REFERER} !^$' ) { print "checked"; last; }
        }
        close $htaccess_fh;
    }
    else {
        print "<b>Error: while opening $htaccess</b>\n";
    }
    return "";
}

## DEPRECATED: use api2_list_hotlinks instead
sub hotlinkingenabled {
    if ( !main::hasfeature("hotlink") ) { return (); }

    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";

    if ( !-e $htaccess ) {
    }
    elsif ( open my $htaccess_fh, "<", $htaccess ) {
        while ( my $line = readline $htaccess_fh ) {
            if ( $line =~ /^\s*RewriteCond/i && $line =~ /\%\{HTTP_REFERER\}/ ) {
                return "enabled";
            }
        }
        close $htaccess_fh;
    }
    else {
        print "<b>Error: while opening $htaccess</b>\n";
    }

    return "disabled";
}

## DEPRECATED: use api2_list_hotlinks instead
sub gethotlinkext {
    if ( !main::hasfeature("hotlink") ) { return (); }

    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";
    my $extension;
    my $nextrule = 1;

    if ( !-e $htaccess ) {
        Cpanel::FileUtils::TouchFile::touchfile($htaccess);
    }

    if ( open my $htaccess_fh, "<", "$htaccess" ) {
        while ( my $line = readline $htaccess_fh ) {
            if ( $line =~ /^RewriteCond/i && $line =~ /\%\{HTTP_REFERER\}/ ) {
                $nextrule = 1;
            }
            elsif ( $nextrule && $line =~ /^RewriteRule/i ) {
                $nextrule = 0;
                ( undef, $extension, undef ) = split( /\s+/, $line );
                $extension =~ /\(([^\)]+)\)/;
                $extension = $1;
                $extension =~ s/\|/\,/g;
                $extension =~ s/\s//g;
                $extension =~ s/\n//g;
                print $extension;
            }
        }
        close $htaccess_fh;
    }
    else {
        print "<b>Error: while opening $htaccess</b>\n";
    }

    if ( $extension eq "" ) {
        print "jpg,jpeg,gif,png,bmp";
    }
}

## DEPRECATED: use api2_list_hotlinks instead
sub gethotlinkrurl {
    if ( !main::hasfeature("hotlink") ) { return (); }

    my $htaccess = "$Cpanel::homedir/public_html/.htaccess";

    if ( !-e $htaccess ) {
        Cpanel::FileUtils::TouchFile::touchfile($htaccess);
        return "";
    }

    my $nextrule = 0;
    if ( open my $htaccess_fh, "<", "$htaccess" ) {
        while ( my $line = readline $htaccess_fh ) {
            if ( $line =~ /^\s*RewriteCond/i && $line =~ /\%\{HTTP_REFERER\}/ ) {
                $nextrule = 1;
            }
            elsif ( $nextrule && $line =~ /^\s*RewriteRule/i ) {
                my $url;
                $nextrule = 0;
                ( undef, undef, $url ) = split( / /, $line );
                if ( $url ne "-" ) {
                    print $url;
                }
            }
        }
        close $htaccess_fh;
    }
    else {
        print "<b>Error: while opening $htaccess</b>\n";
    }
}

## combines the following API1 calls: gethotlinkurls, linkallownull,
##   hotlinkingenabled, gethotlinkext, gethotlinkrurl
## DEPRECATED
sub api2_list_hotlinks {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Mime", "list_hotlinks", { 'api.quiet' => 1 } );
    return $result->data();
}

## a changed version of these four exist in Cpanel::API::Mime; the return signature had
##   to change for the &user_* functions, as they used to print, and now need to account
##   for an optional error message; the &system_* were changed to reflect unification
sub user_mime {
    my ( $mime, $msg ) = Cpanel::API::Mime::_user_mime();
    print $msg if ( defined $msg );
    return defined $mime ? %$mime : ();
}

sub system_mime {
    my ($mime) = Cpanel::API::Mime::_system_mime();
    return defined $mime ? %$mime : ();
}

sub user_handlers {
    my ( $handlers, $msg ) = Cpanel::API::Mime::_user_handlers();
    print $msg if ( defined $msg );
    return defined $handlers ? %$handlers : ();
}

sub system_handlers {
    my ($handlers) = Cpanel::API::Mime::_system_handlers();
    return defined $handlers ? %$handlers : ();
}

##################################################

my $allow_demo = { allow_demo => 1 };

our %API = (
    listhandlers    => $allow_demo,
    listmime        => $allow_demo,
    redirectname    => $allow_demo,
    redirecturlname => $allow_demo,
    listredirects   => { needs_feature => 'redirects' },
    list_hotlinks   => { needs_feature => 'hotlink' },
);

$_->{'needs_role'} = 'WebServer' for values %API;

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

our $api1 = {
    'del_redirect' => {
        'modify'          => 'none',
        'function'        => \&Cpanel::Mime::del_redirect,    # not allowed to return html
        'needs_role'      => 'WebServer',
        'legacy_function' => 2                                #Cpanel::Api::PRINT_STATUSMSG(), \&Cpanel::Mime::legacy_del_redirect,  -- uses function if not defined -- legacy functions are allowed to print html
    },
    'add_redirect' => {
        'modify'          => 'none',
        'function'        => \&Cpanel::Mime::add_redirect,    #not allowed to return html or print()
        'needs_role'      => 'WebServer',
        'legacy_function' => 2                                #Cpanel::Api::PRINT_STATUSMSG(), \&Cpanel::Mime::legacy_add_redirect,  -- uses function if not defined -- legacy functions are allowed to print html
    }
};

1;
