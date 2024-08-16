
# cpanel - Cpanel/Park.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Park;

use cPstrict;

use Cpanel                   ();
use Cpanel::AdminBin         ();
use Cpanel::DomainLookup     ();
use Cpanel::Encoder::Tiny    ();
use Cpanel::LoadModule       ();
use Cpanel::Validate::Domain ();
our $VERSION = '1.3';

my $DO_SSL_SETUP   = 0;
my $SKIP_SSL_SETUP = 1;

sub Park_init { return 1; }

sub Park_cplistaddons {
    my %SUBS = Cpanel::DomainLookup::listsubdomains();
    my @PSUBS;
    my ( %PN, $pname );

    foreach ( keys %SUBS ) {
        ( $pname, undef ) = split( /_/, $_ );
        s/_/\./g;
        push @PSUBS, $_;
        $PN{$_} = $pname;
    }
    my %PARKED = Cpanel::DomainLookup::getmultiparked(@PSUBS);
    delete $PARKED{ $Cpanel::CPDATA{'DNS'} };
    foreach my $subdomain ( keys %PARKED ) {
        foreach my $parked ( keys %{ $PARKED{$subdomain} } ) {
            $PN{$subdomain} =~ s/\.\.//g;
            my $docroot = $PARKED{$subdomain}{$parked};

            my $rd = 0;
            if ( -e $docroot . '/.htaccess' ) {
                if ( open my $htaccess_fh, '<', $docroot . '/.htaccess' ) {
                    while ( my $line = readline $htaccess_fh ) {
                        if ( $line =~ m/^RedirectMatch\s+/i
                            || ( $line =~ m/^RewriteCond/i && $line =~ m/\Q${parked}\E/i ) ) {
                            $rd = 1;
                        }
                    }
                    close $htaccess_fh;
                }
            }

            if ($rd) {
                print "$parked ($PN{$subdomain}) [redirect]<br />\n";
            }
            else {
                print "$parked ($PN{$subdomain})<br />\n";
            }
        }
    }
}

sub Park_listaddonsop {
    my ( $rdonly, $underscore ) = @_;
    my %SUBS = Cpanel::DomainLookup::listsubdomains();
    my @PSUBS;
    my ( %PN, %FN, $pname, $fname );

    foreach ( keys %SUBS ) {
        $fname = $_;
        ( $pname, undef ) = split( /_/, $_ );
        s/_/\./g;
        $FN{$_} = $fname;
        push( @PSUBS, $_ );
        $PN{$_} = $pname;
    }

    my %PARKED = Cpanel::DomainLookup::getmultiparked(@PSUBS);
    delete $PARKED{ $Cpanel::CPDATA{'DNS'} };
    foreach my $subdomain ( keys %PARKED ) {
        foreach my $parked ( keys %{ $PARKED{$subdomain} } ) {
            $PN{$subdomain} =~ s/\.\.//g;
            my $docroot = $PARKED{$subdomain}{$parked};
            if ($rdonly) {
                my $rd = 0;
                open( HT, "<", "$docroot/.htaccess" );
                while (<HT>) {
                    if ( /^Redirect(Match)? /i || ( /^RewriteCond/i && /\Q${parked}\E/i ) ) {
                        $rd = 1;
                    }
                }
                close(HT);

                next if !$rd;
            }
            if ($underscore) {
                print "<option value=\"$parked,$FN{$subdomain}\">" . $parked . "</option>\n";
            }
            else {
                print "<option value=\"$parked,$subdomain\">" . $parked . "</option>\n";
            }
        }
    }
}

sub _countaddons {
    my $addons = 0;

    # getmultiparked takes no arguments -- we did all this work and then threw is away
    my %PARKED = Cpanel::DomainLookup::getmultiparked();
    delete $PARKED{ $Cpanel::CPDATA{'DNS'} };
    foreach my $subdomain ( keys %PARKED ) {
        $addons += scalar keys %{ $PARKED{$subdomain} };
    }
    return $addons;
}

sub Park_countaddons {
    print _countaddons();
}

sub _getparked {
    my (@PARKED);
    my %MPARKED = Cpanel::DomainLookup::getmultiparked();
    foreach my $parked ( sort keys %{ $MPARKED{ $Cpanel::CPDATA{'DNS'} } } ) {
        next if ( $parked eq '' );    # Shouldn't be necessary
        push( @PARKED, $parked );
    }
    return @PARKED;
}

sub Park_cplistparked {
    my @PARKED = _getparked();
    foreach my $parked (@PARKED) {
        print $parked . "<br />\n";
    }
}

sub Park_listparkedop {
    my @PARKED = _getparked();
    foreach my $parked (@PARKED) {
        print "<option value=\"" . $parked . "\">" . $parked . "</option>\n";
    }
}

sub _countparked {
    my %MPARKED = Cpanel::DomainLookup::getmultiparked();
    return scalar keys %{ $MPARKED{ $Cpanel::CPDATA{'DNS'} } };
}

sub Park_countparked {
    print _countparked();
}

sub api2_park {
    my %CFG = @_;
    my ( $result, $reason ) = _park( $CFG{'domain'}, $CFG{'topdomain'}, $CFG{'disallowdot'} );
    return { 'result' => $result, 'reason' => $reason };
}

sub api2_unpark {
    my %CFG = @_;
    my ( $result, $reason ) = _unpark( $CFG{'domain'}, $CFG{'subdomain'} );
    return { 'result' => $result, 'reason' => $reason };
}

sub Park_unpark {
    my ( $result, $reason ) = _unpark(@_);
    return print Cpanel::Encoder::Tiny::safe_html_encode_str($reason);
}

sub _unpark {
    my ( $domain, $is_addon ) = @_;

    $Cpanel::context = 'park';

    # Do not change to Cpanel::hasfeature as it will break WHM
    if ( !main::hasfeature('parkeddomains') && !main::hasfeature('addondomains') ) {
        $Cpanel::CPERROR{'park'} = "This feature is not enabled";
        return ( 0, $Cpanel::CPERROR{'park'} );
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        print 'Sorry, this feature is disabled in demo mode.';
        return ( 0, $Cpanel::CPERROR{'park'} );
    }
    if ( $domain =~ m/\,/ ) {
        ( $domain, $is_addon ) = split( /\,/, $domain );
    }

    # If we are actually parked on an addon, but didn't get that parameter,
    # make sure we have valid parameters.
    $is_addon ||= _get_addon_parent($domain);

    $domain =~ /([\-a-z\.0-9]*)/i;
    $domain = $1;

    if ( my $err = _get_ddns_subdomains_err($domain) ) {
        return ( 0, $err );
    }

    my $action = $is_addon ? 'DELADDON' : 'DEL';
    if ( $is_addon && $is_addon !~ m/_/ && $is_addon =~ m/\.\Q$Cpanel::CPDATA{'DNS'}\E$/i ) {
        $is_addon =~ s/\./_/;    # substitute only the first one
    }
    my $res = Cpanel::AdminBin::adminrun( 'park', $action, $domain, $is_addon );
    if ( !$Cpanel::CPERROR{'park'} ) {
        return ( 1, $res );
    }
    else {
        return ( 0, $Cpanel::CPERROR{'park'} );
    }
}

sub _get_ddns_subdomains_err ($zone) {
    require Cpanel::DynamicDNS::UserUtils;
    my $count = Cpanel::DynamicDNS::UserUtils::get_ddns_domains_for_zone($zone);

    return $count && Cpanel::DynamicDNS::UserUtils::ddns_zone_error( $count, $zone );
}

# Given a domain, return the parent, if the domain is indeed parked on top
# of something.  Otherwise, undef.
sub _get_parked_parent {
    my ($domain) = @_;

    my %PARKED = Cpanel::DomainLookup::getmultiparked();
    foreach my $subdomain ( keys %PARKED ) {
        return $subdomain if ( exists $PARKED{$subdomain}->{$domain} );
    }
    return;
}

# Given a domain, return the parent if it is an addon domain.  Otherwise undef.
sub _get_addon_parent {
    my ($domain) = @_;

    my $parent = _get_parked_parent($domain);
    return if ( $parent eq $Cpanel::CPDATA{'DNS'} );
    return $parent;
}

sub Park_park {
    my ( $result, $reason ) = _park(@_);
    ## case 30334: removed explicit call to ::EventHandler subsystem
    return print Cpanel::Encoder::Tiny::safe_html_encode_str($reason);
}

sub _park {
    my ( $domain, $topdomain, $disallowdot, $do_ssl_setup, $phpfpm_domain ) = @_;
    $Cpanel::context = 'park';
    if ( !$domain ) {
        $Cpanel::CPERROR{'park'} = 'domain not specified';
        return ( 0, $Cpanel::CPERROR{'park'} );
    }

    $phpfpm_domain = 0 if !defined $phpfpm_domain;

    $domain =~ s/^www\.//g;
    $domain =~ tr/A-Z/a-z/;
    $domain =~ /([\-a-z\.0-9]*)/i;
    $domain = $1;
    if ( !Cpanel::Validate::Domain::is_valid_cpanel_domain( $domain, my $why ) ) {
        $Cpanel::CPERROR{'park'} = "Invalid domain specified: $why";
        return ( 0, $Cpanel::CPERROR{'park'} );
    }

    # Do not change to Cpanel::hasfeature as it will break WHM
    if ( !main::hasfeature('parkeddomains') && !main::hasfeature('addondomains') ) {
        $Cpanel::CPERROR{'park'} = 'This feature is not enabled';
        return ( 0, $Cpanel::CPERROR{'park'} );
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $Cpanel::CPERROR{'park'} = 'Sorry, this feature is disabled in demo mode.';
        print 'Sorry, this feature is disabled in demo mode.';
        return ( 0, $Cpanel::CPERROR{'park'} );
    }

    $Cpanel::CPERROR{'park'} = 0;
    if ( defined $topdomain ) {
        if ($disallowdot) { $topdomain =~ s/\.//g; }
        $topdomain = $topdomain . '.' . $Cpanel::CPDATA{'DNS'};
    }

    # Parked Domain ACL
    # Do not change to Cpanel::hasfeature as it will break WHM
    if ( defined $topdomain && $topdomain eq $Cpanel::CPDATA{'DNS'} && !main::hasfeature('parkeddomains') ) {
        $Cpanel::CPERROR{'park'} = 'This feature is not enabled';
        return ( 0, $Cpanel::CPERROR{'park'} );
    }

    # topdomain is null for parked domains.
    my $res = Cpanel::AdminBin::adminrun( 'park', 'ADD', $domain, $topdomain, $do_ssl_setup ? $DO_SSL_SETUP : $SKIP_SSL_SETUP, $phpfpm_domain );
    if ( !$Cpanel::CPERROR{'park'} ) {
        return ( 1, $res );
    }
    else {
        return ( 0, $Cpanel::CPERROR{'park'} );
    }
}

sub api2_listparkeddomains {
    my %OPTS  = @_;
    my $regex = $OPTS{'regex'};
    my @RSD;
    my %MPARKED = Cpanel::DomainLookup::getmultiparked();
    require Cpanel::HttpUtils::Htaccess;
    foreach my $parked ( sort keys %{ $MPARKED{ $Cpanel::CPDATA{'DNS'} } } ) {
        next if ( $parked eq '' );    # Shouldn't be necessary
        if ( defined $regex && $regex ne '' && $parked !~ /$regex/i ) { next; }

        my $dir    = $MPARKED{ $Cpanel::CPDATA{'DNS'} }{$parked};
        my $reldir = $dir;
        $reldir =~ s/^(\Q$Cpanel::homedir\E|\Q$Cpanel::abshomedir\E)\/?/home:/g;

        my $basedir = $reldir;
        $basedir =~ s/^home://g;
        my ( $status, $url, $defined ) = Cpanel::HttpUtils::Htaccess::getrewriteinfo( $dir, $parked );
        $status =~ s/\%\{REQUEST_URI\}/\//g;

        my $data = {
            'domain'                => $parked,
            'dir'                   => $dir,
            'basedir'               => $basedir,
            'reldir'                => $reldir,
            'status'                => $defined ? $url : $status,
            'web_subdomain_aliases' => _get_web_aliases( $parked, $Cpanel::CPDATA{'DNS'} ),
        };

        if ( $OPTS{'return_https_redirect_status'} ) {

            #Then I need to set can_https_redirect and is_https_redirecting
            Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::HttpsRedirect');
            Cpanel::HttpUtils::HttpsRedirect::get_userdata_with_https_redirect_info( $parked, $Cpanel::user, $data );
        }

        push @RSD, $data;
    }
    return @RSD;
}

sub Park_getredirecturl {
    my $domain = shift;
    require Cpanel::HttpUtils::Htaccess;
    my ( $status, $url, $rd ) = Cpanel::HttpUtils::Htaccess::getrewriteinfo( $Cpanel::homedir . '/public_html', $domain );
    $url =~ s/\%\{REQUEST_URI\}/\//g;
    $url =~ s/\$1//g;
    if ( !$url ) { $url = 'http://'; }
    return print $url;
}

sub _getrelparkeddir {
    my $parked  = shift;
    my %MPARKED = Cpanel::DomainLookup::getmultiparked();
    my $dir     = $MPARKED{ $Cpanel::CPDATA{'DNS'} }{$parked};
    my $reldir  = $dir;
    $reldir =~ s/^(\Q$Cpanel::homedir\E|\Q$Cpanel::abshomedir\E)\/?//g;
    return $reldir;
}

sub Park_setredirecturl {

    # Do not change to Cpanel::hasfeature as it will break WHM
    if ( !main::hasfeature("addondomains") && !main::hasfeature('parkeddomains') ) {
        $Cpanel::CPERROR{'park'} = "This feature is not enabled";
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $Cpanel::CPERROR{'park'} = 'Sorry, this feature is disabled in demo mode.';
        print 'Sorry, this feature is disabled in demo mode.';
        return;
    }

    my $domain = shift;
    my $reldir = _getrelparkeddir($domain);
    my $url    = shift;

    require Cpanel::HttpUtils::Htaccess;
    if ( !$url || $url eq 'http://' ) {
        Cpanel::HttpUtils::Htaccess::disableredirection( $Cpanel::homedir . '/' . $reldir, $domain );
        print qq{nowhere (<b><font color="#FF0000">Redirection Disabled!</font></b>)\n};
        return;
    }
    else {
        my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::setupredirection( 'docroot' => $Cpanel::homedir . '/' . $reldir, 'domain' => $domain, 'redirecturl' => $url );

        if ( !$status ) {
            print 'unchanged', '(<b><font color="#FF0000">' . $msg . "</font></b>)";
            return;
        }
    }
    print Cpanel::Encoder::Tiny::safe_html_encode_str($url);
    return;
}

sub Park_disableredirect {

    # Do not change to Cpanel::hasfeature as it will break WHM
    if ( !main::hasfeature("addondomains") && !main::hasfeature('parkeddomains') ) {
        $Cpanel::CPERROR{'park'} = "This feature is not enabled";
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $Cpanel::CPERROR{'park'} = 'Sorry, this feature is disabled in demo mode.';
        print 'Sorry, this feature is disabled in demo mode.';
        return;
    }

    my $domain = shift;
    my $reldir = _getrelparkeddir($domain);

    require Cpanel::HttpUtils::Htaccess;
    Cpanel::HttpUtils::Htaccess::disableredirection( $Cpanel::homedir . '/' . $reldir, $domain );
    print qq{nowhere (<b><font color="#FF0000">Redirection Disabled!</font></b>)\n};
    return;
}

sub api2_listaddondomains {
    my %OPTS  = @_;
    my $regex = $OPTS{'regex'};
    my %SUBS  = Cpanel::DomainLookup::listsubdomains();
    my @PSUBS;
    my ( %PN, %FN, $pname, $fname );

    my @RSD;
    foreach ( keys %SUBS ) {
        $fname = $_;
        ( $pname, undef ) = split( /_/, $_ );
        s/_/\./g;
        $FN{$_} = $fname;
        push @PSUBS, $_;
        $PN{$_} = $pname;
    }

    require Cpanel::HttpUtils::Htaccess;
    my %PARKED = Cpanel::DomainLookup::getmultiparked(@PSUBS);
    delete $PARKED{ $Cpanel::CPDATA{'DNS'} };
    foreach my $subdomain ( keys %PARKED ) {
        foreach my $parked ( keys %{ $PARKED{$subdomain} } ) {
            if ( defined $regex && $regex ne '' && $parked !~ /$regex/i ) { next; }
            my $docroot = $PARKED{$subdomain}{$parked};
            $PN{$subdomain} =~ s/\.\.//g;
            my ($status) = Cpanel::HttpUtils::Htaccess::getrewriteinfo( $docroot, $parked );
            $status =~ s/\%\{REQUEST_URI\}/\//g;

            my $rootdomain;
            ( undef, $rootdomain ) = split( /_/, $FN{$subdomain}, 2 );
            my $dir    = $PARKED{$subdomain}{$parked};
            my $reldir = $dir;
            $reldir =~ s/^(?:\Q$Cpanel::homedir\E|\Q$Cpanel::abshomedir\E)\/?/home:/g;
            my $basedir = $reldir;
            $basedir =~ s/^home://g;

            my $data = {
                'domain'                => $parked,
                'dir'                   => $dir,
                'reldir'                => $reldir,
                'basedir'               => $basedir,
                'status'                => $status,
                'domainkey'             => $FN{$subdomain},
                'subdomain'             => $PN{$subdomain},
                'rootdomain'            => $rootdomain,
                'fullsubdomain'         => $subdomain,
                'web_subdomain_aliases' => _get_web_aliases( $parked, $subdomain ),
            };

            if ( $OPTS{'return_https_redirect_status'} ) {

                #Then I need to set can_https_redirect and is_https_redirecting
                Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::HttpsRedirect');
                Cpanel::HttpUtils::HttpsRedirect::get_userdata_with_https_redirect_info( $parked, $Cpanel::user, $data );
            }

            push( @RSD, $data );
        }

    }

    @RSD = sort { $a->{'domain'} cmp $b->{'domain'} } @RSD;

    return @RSD;
}

sub _get_web_aliases {
    require Cpanel::WebVhosts::Aliases;
    return [ Cpanel::WebVhosts::Aliases::get_builtin_alias_subdomains(@_) ];
}

my $allow_demo = { allow_demo => 1 };

my $parked_addon_domains_feature = {
    needs_feature => { match => 'any', features => [qw(parkeddomains addondomains)] },
};

our %API = (
    listaddondomains  => $allow_demo,
    listparkeddomains => $allow_demo,
    park              => $parked_addon_domains_feature,
    unpark            => $parked_addon_domains_feature,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
