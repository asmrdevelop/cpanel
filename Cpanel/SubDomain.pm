
# cpanel - Cpanel/SubDomain.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::SubDomain;

require 5.014;    # for s///r

use strict;
use warnings;

use Try::Tiny;

use Cpanel::AdminBin::Call       ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::Data::Result         ();
use Cpanel::SafeDir::MK          ();
use Cpanel                       ();
use Cpanel::Debug                ();
use Cpanel::Encoder::Tiny        ();
use Cpanel::Exception            ();
use Cpanel::SafeDir::Fixup       ();
use Cpanel::DomainLookup         ();
use Cpanel::FileUtils::Write     ();
use Cpanel::Validate::SubDomain  ();
use Cpanel::WildcardDomain       ();
use Cpanel::Path::Normalize      ();
use Cpanel::LoadModule           ();
use Cpanel::Locale               ();
use Cpanel::Exception            ();

our ( @ISA, @EXPORT, $VERSION );
$VERSION = 1.3;

my %SubDomains;
my $subdomaincache;

our $DO_SSL_SETUP   = 0;
our $SKIP_SSL_SETUP = 1;

# banned on exact match, checked as absolute path appended to $Cpanel::abshomedir
our $RESERVED_DOCROOTS = [qw(.cpanel .trash etc mail ssl tmp logs .spamassassin .htpasswds var cgi-bin .ssh perl5)];

sub _REWRITE_INFO_CACHE_PATH {
    die "Need homedir set!" if !$Cpanel::homedir;

    return "$Cpanel::homedir/.cpanel/caches/rewriteinfo";
}

sub _check_perms {
    my $locale = Cpanel::Locale->get_handle();
    if ( !main::hasfeature('subdomains') ) {
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext('This feature is not enabled.');
        return;
    }
    return 1;
}

sub _check_demo {
    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        my $text = Cpanel::Exception::create('ForbiddenInDemoMode')->to_locale_string_no_id();
        $Cpanel::CPERROR{'subdomain'} = $text;
        print $text;
        return;
    }
    return 1;
}

sub setsuburl {
    my ( $sub, $url ) = @_;
    if ( !_check_perms() || !_check_demo() ) {
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    my $wholesub;
    my $redirectm;

    if ( $sub =~ tr/\,// ) {
        ( $redirectm, $wholesub ) = split( /\,/, $sub );
    }
    else {
        $wholesub  = $sub;
        $redirectm = $sub;
    }
    $wholesub =~ s/_/\./g;

    $redirectm =~ s/_/\./g;

    if ( $sub =~ tr/_// ) {
        ( $sub, undef ) = split( /_/, $sub );
    }
    $url =~ s/\n//g;

    my $reldir = _getrelsubdomaindir($wholesub);

    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::Htaccess');
    if ( !$url || $url eq 'http://' ) {
        Cpanel::HttpUtils::Htaccess::disableredirection( $Cpanel::homedir . '/' . $reldir, $redirectm );
        return qq{nowhere (<b><font color="#FF0000">Redirection Disabled!</font></b>)\n};
    }
    else {
        my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::setupredirection( 'docroot' => $Cpanel::homedir . '/' . $reldir, 'domain' => $redirectm, 'redirecturl' => $url );

        if ( !$status ) {
            return 'unchanged', '(<b<font color="#FF0000">' . Cpanel::Encoder::Tiny::safe_html_encode_str($msg) . "</font></b>)\n";
        }
    }
    return Cpanel::Encoder::Tiny::safe_html_encode_str($url);
}

sub disablesubrd {
    my ($sub) = @_;
    if ( !_check_perms() || !_check_demo() ) {
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    my $wholesub;
    my $redirectm;

    if ( $sub =~ tr/\,// ) {
        ( $redirectm, $wholesub ) = split( /\,/, $sub );
    }
    else {
        $wholesub  = $sub;
        $redirectm = $sub;
    }

    $wholesub  =~ s/_/\./g;
    $redirectm =~ s/_/\./g;

    if ( $sub =~ tr/_// ) {
        $sub = ( split( /_/, $sub ) )[0];
    }
    my $reldir = _getrelsubdomaindir($wholesub);

    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::Htaccess');
    my ( $status, $msg ) = Cpanel::HttpUtils::Htaccess::disableredirection( $Cpanel::homedir . '/' . $reldir, $redirectm );

    if ( !$status ) {
        return qq{<br><font color="#FF0000">Redirection can not be disabled: $msg</font></b>\n };
    }

    return qq{<b>Redirection has been disabled on $redirectm.</b>\n};
}

sub subdomainurl {
    my ($sub) = @_;
    if ( !_check_perms() ) {
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    my $wholesub;
    my $redirectm;
    if ( $sub =~ tr/\,// ) {
        ( $redirectm, $wholesub ) = split( /\,/, $sub );
        $wholesub =~ s/_/\./g;
    }
    else {
        $sub =~ s/_/\./g;
        $wholesub  = $sub;
        $redirectm = $sub;
    }
    my $reldir = _getrelsubdomaindir($wholesub);
    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::Htaccess');
    my ( $status, $url, $rd ) = Cpanel::HttpUtils::Htaccess::getrewriteinfo( $Cpanel::homedir . '/' . $reldir, $redirectm );
    $url =~ s/\$1//g;
    $url =~ s/\%\{REQUEST_URI\}/\//g;
    if ( !$url ) { $url = 'http://'; }

    return Cpanel::Encoder::Tiny::safe_html_encode_str($url);
}

sub cplistsubdomains {
    my %RSD = Cpanel::DomainLookup::listsubdomains();
    my $now = time();
    load_rewriteinfo_cache();
    my @SD;
    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::Htaccess');
    foreach my $d ( sort keys %RSD ) {
        my ( $sub, $domain ) = split( /_/, $d );
        my $subdomain = $sub . '.' . $domain;
        my $dir       = $RSD{$d};
        my $reldir    = $dir;
        $reldir =~ s/^(\Q$Cpanel::homedir\E|\Q$Cpanel::abshomedir\E)\/?//g;

        my ( $status, $url, $rd ) = Cpanel::HttpUtils::Htaccess::getrewriteinfo( $Cpanel::homedir . '/' . $reldir, $subdomain, $now );
        $url =~ s/\%\{REQUEST_URI\}/\//g;

        if ($rd) {
            push( @SD, "$subdomain ($reldir) [redirect]" );
        }
        else {
            push( @SD, "$subdomain ($reldir)" );
        }
    }
    save_rewriteinfo_cache();
    return @SD;
}

sub countsubdomains {
    my %SD = Cpanel::DomainLookup::listsubdomains();
    return scalar keys %SD;
}

# WebServer role is required via cpanel.pl.
sub addsubdomain {
    $Cpanel::context = 'subdomain';
    my ( $result, $reason ) = _addsubdomain(@_);
    ## case 30334: removed explicit call to ::EventHandler subsystem
    print Cpanel::Encoder::Tiny::safe_html_encode_str($reason);

    return 1;
}

sub api2_changedocroot {
    my %CFG = @_;

    $Cpanel::context = 'subdomain';

    my ( $result, $reason, $dir ) = _changedocroot( $CFG{'subdomain'}, $CFG{'rootdomain'}, $CFG{'dir'} );
    my $reldir = $dir;
    $reldir =~ s/^(\Q$Cpanel::homedir\E|\Q$Cpanel::abshomedir\E)\/?//g;

    return { 'result' => $result, 'reason' => $reason, 'dir' => $dir, 'reldir' => $reldir };
}

sub _changedocroot {
    my ( $subdomain, $rootdomain, $dir ) = @_;

    $Cpanel::context = 'subdomain';

    if ( !defined $subdomain || $subdomain eq '' || !defined $rootdomain || $rootdomain eq '' ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext('You must specify a main domain.');
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }
    elsif ( $subdomain eq 'www' ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext( 'You cannot create the “[_1]” subdomain, because the system adds the “[_1]” subdomain to all newly-created domains.', 'www' );
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    # check $thisdir after strip/replace
    if ( !$dir ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext('You must specify a new document root.');
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    $dir = q{/} . $dir;

    # IMPORTANT: Ensure that Cpanel::Validate::DocumentRoot
    # rejects everything that this logic coerces out.
    #
    # strip or replace characters
    $dir =~ s{\s+}{}g;
    $dir =~ s/\\//g;
    $dir =~ s{//+}{/}g;
    $dir =~ tr{<>}{}d;

    # strip $HOME if provided
    $dir =~ s/\A$Cpanel::abshomedir\///g;

    # collapse relative paths
    my $thisdir = Cpanel::Path::Normalize::normalize("$Cpanel::abshomedir/$dir");
    $thisdir = Cpanel::SafeDir::Fixup::homedirfixup($thisdir);

    if ( $Cpanel::CONF{'publichtmlsubsonly'} ) {
        $thisdir = Cpanel::SafeDir::Fixup::publichtmldirfixup($thisdir);
    }

    # reject $thisdir and /$thisdir if $thisdir is RESERVED
    elsif ( grep { "$Cpanel::abshomedir/$_" =~ m/\Q$thisdir\E\/?$/ } @$RESERVED_DOCROOTS or $thisdir eq $Cpanel::abshomedir ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext( 'The system reserves the “[_1]” document root. You must specify a document root that the system does not reserve.', $thisdir );
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    Cpanel::SafeDir::MK::safemkdir( $thisdir, '0755' );
    my $errstr = $! . '';
    if ( !-d $thisdir ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = Cpanel::Exception::create( 'IO::DirectoryCreateError', [ $thisdir, $errstr ] )->to_locale_string();
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    $subdomain =~ s/^\s+//g;
    $subdomain =~ s/\s+$//g;
    $subdomain =~ s/^www\.//g;
    $subdomain =~ tr/A-Z/a-z/;
    $subdomain =~ s/\.$//;       # Trim any trailing dot: Case 828

    my $result = Cpanel::Data::Result::try(
        sub {
            Cpanel::AdminBin::Call::call(
                'Cpanel', 'subdomain', 'CHANGEDOCROOT',
                "$subdomain.$rootdomain", $thisdir,
            );
        }
    );

    if ( $result->error() ) {
        my $str = Cpanel::Exception::get_string( $result->error() );
        $Cpanel::CPERROR{'subdomain'} = $str;

        return ( 0, $str, $thisdir );
    }

    return ( 1, $result->get()->{'message'}, $thisdir );
}

sub api2_addsubdomain {
    $Cpanel::context = 'subdomain';
    my %CFG = @_;
    my ( $result, $reason ) = _addsubdomain( $CFG{'domain'}, $CFG{'rootdomain'}, $CFG{'canoff'}, $CFG{'disallowdot'}, $CFG{'dir'} );

    return { 'result' => $result, 'reason' => $reason };
}

sub _addsubdomain {    ## no critic qw(ProhibitManyArgs)
    my ( $domain, $rootdomain, $canoff, $disallowdot, $dir, $skip_ssl_setup, $skip_ap_restart, $skip_phpfpm ) = @_;

    tr/A-Z/a-z/ for ( $domain, $rootdomain );

    $Cpanel::context = 'subdomain';
    if ( !_check_perms() || !_check_demo() ) {
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    if ( !defined $rootdomain || $rootdomain eq '' ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext('You must specify a main domain.');
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    if ( !defined $domain || $domain eq '' ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext('You must specify a subdomain.');
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    $skip_ap_restart = 0 if !defined $skip_ap_restart;
    $skip_phpfpm     = 0 if !defined $skip_phpfpm;

    $dir = Cpanel::WildcardDomain::encode_wildcard_domain($domain) unless $dir;

    $dir = q{/} . $dir;
    $dir =~ s{\s+}{}g;
    $dir =~ s{\\}{}g;
    $dir =~ s{//+}{/}g;
    $dir =~ tr{<>}{}d;

    # strip $HOME if provided
    $dir =~ s/\A$Cpanel::abshomedir\/?//g;

    # collapse relative paths
    my $thisdir = Cpanel::Path::Normalize::normalize("$Cpanel::abshomedir/$dir");
    $thisdir = Cpanel::SafeDir::Fixup::homedirfixup($thisdir);

    if ( $Cpanel::CONF{'publichtmlsubsonly'} ) {
        $thisdir = Cpanel::SafeDir::Fixup::publichtmldirfixup($thisdir);
    }

    # reject $thisdir and /$thisdir if $thisdir is RESERVED
    elsif ( grep { "$Cpanel::abshomedir/$_" =~ m/\Q$thisdir\E\/?$/ } @$RESERVED_DOCROOTS or $thisdir eq $Cpanel::abshomedir ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext( 'The system reserves the “[_1]” document root. You must specify a document root that the system does not reserve.', $thisdir );
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    Cpanel::SafeDir::MK::safemkdir( $thisdir, '0755' );
    my $errstr = $! . '';
    if ( !-d $thisdir ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = Cpanel::Exception::create( 'IO::DirectoryCreateError', [ $thisdir, $errstr ] )->to_locale_string();
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    $domain =~ s/^\s+//g;
    $domain =~ s/\s+$//g;
    $domain =~ s/^www\.//g;
    if ($disallowdot) {
        $domain =~ s/[.]//g;
    }
    else {
        $domain =~ s/\.$//;    # Trim any trailing dot: Case 828
    }

    if ( !Cpanel::Validate::SubDomain::is_valid($domain) ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext('You must specify a valid subdomain.');
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }
    elsif ( Cpanel::Validate::SubDomain::is_reserved($domain) ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext( 'You cannot create the “[_1]” subdomain, because the system adds the “[_1]” subdomain to all newly-created domains.', $domain );
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    my $result = Cpanel::Data::Result::try(
        sub {

            # The following used to be done in the admin layer but
            # as of v86 needs to be done in unprivileged code since
            # the admin code no longer coerces invalid input:
            my $dns = $Cpanel::CPDATA{'DNS'};
            $rootdomain = lc $rootdomain;
            $domain =~ s/\.\Q${dns}\E$//g;
            $domain =~ s/^\.//g;

            Cpanel::AdminBin::Call::call(
                'Cpanel', 'subdomain', 'ADD',
                subdomain           => $domain,
                rootdomain          => $rootdomain,
                skip_ssl_setup      => $skip_ssl_setup ? 1 : 0,
                documentroot        => $thisdir,
                usecannameoff       => $canoff,
                skip_restart_apache => $skip_ap_restart,
                skip_phpfpm         => $skip_phpfpm,
            );
        }
    );

    if ( $result->error() ) {
        my $str = Cpanel::Exception::get_string( $result->error() );

        $Cpanel::CPERROR{'subdomain'} = $str;

        return ( 0, $str );
    }

    return ( 1, $result->get()->{'message'} );
}

## note: this is no longer called by x3; suspect not used at all.
sub delsubdomain {
    $Cpanel::context = 'subdomain';
    my ( $result, $reason ) = _delsubdomain(@_);
    ## case 30334: removed explicit call to ::EventHandler subsystem
    print $reason;
}

sub api2_delsubdomain {
    $Cpanel::context = 'subdomain';
    my %CFG = @_;
    my ( $result, $reason ) = _delsubdomain( $CFG{'domain'}, $CFG{'disallowdot'} );
    return { 'result' => $result, 'reason' => $reason };
}

# NB: This function is called externally.
sub _delsubdomain {
    my ( $domain, $disallowdot ) = @_;
    my $rootdomain = '';

    $Cpanel::context = 'subdomain';
    if ( !_check_perms() || !_check_demo() ) {
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    if ( !defined $domain || $domain eq '' ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'subdomain'} = $locale->maketext('You must specify a subdomain.');
        return ( 0, $Cpanel::CPERROR{'subdomain'} );
    }

    if ( $domain =~ tr/\,// ) {
        ( undef, $domain ) = split( /\,/, $domain );
        my (@RD) = split( /\./, $domain );
        $rootdomain = $domain;
        $domain     = $RD[0];
        $rootdomain =~ s/^${domain}\.//g;
    }
    if ( $domain =~ tr/_// ) {
        ( $domain, $rootdomain ) = split( /_/, $domain );
    }

    if ($disallowdot) { $domain =~ s/\.//g; }

    my %PARKED = Cpanel::DomainLookup::getmultiparked();
    delete $PARKED{ $Cpanel::CPDATA{'DNS'} };

    if ( $domain ne '*' ) {
        my $subdomain = "$domain.$rootdomain" =~ s/\.$//r;
        if ( exists $PARKED{$subdomain} ) {
            my $locale = Cpanel::Locale->get_handle();
            my @parked = keys %{ $PARKED{$subdomain} };
            $Cpanel::CPERROR{'subdomain'} = $locale->maketext( 'The “[_1]” subdomain links to the following addon [numerate,_2,domain,domains]: [list_and_quoted,_3]. You must remove the addon [numerate,_2,domain,domains] before you remove the subdomain.', $domain, scalar(@parked), \@parked );
            return ( 0, $Cpanel::CPERROR{'subdomain'} );
        }
    }

    # The docs say that this API requires that “domain” separate the
    # subdomain label(s) from the base domain with an underscore, but
    # it also happened to work when a plain FQDN was given. This preserves
    # that functionality:
    my $fqdn = "$domain.$rootdomain";
    $fqdn =~ s<\.\z><>;

    my $result = Cpanel::Data::Result::try(
        sub {
            Cpanel::AdminBin::Call::call(
                'Cpanel', 'subdomain', 'DEL',
                domain => $fqdn,
            );
        }
    );

    if ( $result->error() ) {
        my $str = Cpanel::Exception::get_string( $result->error() );

        $Cpanel::CPERROR{'subdomain'} = $str;
        return ( 0, $str );
    }

    return ( 1, $result->get()->{'message'} );
}

sub rootdomains {    ## no critic qw(Unpack)
    my @root_domains;
    my %DOMAIN_MAP = map { $_ => 1 } @_;
    delete $DOMAIN_MAP{''};    #jic
  DOMAIN_MAP_LOOP:
    foreach my $domain ( keys %DOMAIN_MAP ) {
        my @DNSPATH = split( /\./, $domain );
        while ( shift(@DNSPATH) && $#DNSPATH >= 1 ) {
            my $testdomain = join( '.', @DNSPATH );
            if ( $DOMAIN_MAP{$testdomain} ) {
                next DOMAIN_MAP_LOOP;
            }
        }
        push @root_domains, $domain;
    }
    return @root_domains;
}

sub resolvesymlinks {
    my ($path) = @_;
    return Cpanel::resolvesymlinks($path);
}

sub api2_validregex {
    return [$Cpanel::Validate::SubDomain::REGEX];
}

sub api2_getreservedsubdomains {
    return [ keys %Cpanel::Validate::SubDomain::RESERVED_SUBDOMAINS ];
}

my $subdomain_feature_deny_demo = { needs_feature => 'subdomains' };

our %API = (
    'addsubdomain' => {
        needs_role => 'WebServer',
    },
    'changedocroot'         => $subdomain_feature_deny_demo,
    'delsubdomain'          => $subdomain_feature_deny_demo,
    'getreservedsubdomains' => {
        'engine'     => 'array',
        'datapoints' => ['subdomain'],
        allow_demo   => 1,
    },
    'listsubdomains' => { allow_demo => 1 },
    'validregex'     => {
        'engine'     => 'array',
        'datapoints' => ['0'],
        allow_demo   => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _getrelsubdomaindir {
    my $fullsubdomain = shift;
    my %RD;
    my %SD = Cpanel::DomainLookup::listsubdomains();
    foreach my $sd ( keys %SD ) {
        my $rd = $sd;
        $rd =~ s/_/\./g;
        $RD{$rd} = $SD{$sd};
    }
    my $dir    = $RD{$fullsubdomain};
    my $reldir = $dir;
    $reldir =~ s/^(\Q$Cpanel::homedir\E|\Q$Cpanel::abshomedir\E)\/?//g;
    return $reldir;
}

sub api2_listsubdomains {
    my %OPTS = @_;
    my $regex;
    if ( $OPTS{'regex'} ) {
        eval {
            local $SIG{'__DIE__'} = sub { return };
            $regex = qr/$OPTS{'regex'}/i;
        };
        if ( !$regex ) {
            my $errstr = $@;
            my $locale = Cpanel::Locale->get_handle();
            $Cpanel::CPERROR{'subdomain'} = $locale->maketext( 'The “[_1]” parameter must be a valid Perl regular expression. The system returned the following error: “[_2]”.', 'regex', $errstr );
            return;
        }
    }

    my %SD = Cpanel::DomainLookup::listsubdomains();
    my @RSD;

    my $now = time();
    load_rewriteinfo_cache();
    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::Htaccess');
    Cpanel::LoadModule::load_perl_module('Cpanel::WebVhosts::Aliases');
    my ( $dir, $reldir, $fulldomain, $subdomain, $rootdomain, $basedir, $status, $url, $rd );
    foreach my $sd ( sort keys %SD ) {
        $reldir = $dir = $SD{$sd};
        $reldir =~ s/^(\Q$Cpanel::homedir\E|\Q$Cpanel::abshomedir\E)\/?/home:/g;
        $fulldomain = $sd;
        $fulldomain =~ s/\_/\./g;
        if ( defined $regex && $regex ne '' && $fulldomain !~ /$regex/i ) { next; }
        ( $subdomain, $rootdomain ) = split( /_/, $sd );
        $basedir = $reldir;
        $basedir =~ s/^home://;
        ( $status, $url, $rd ) = Cpanel::HttpUtils::Htaccess::getrewriteinfo( $Cpanel::homedir . '/' . $basedir, $fulldomain, $now );
        $url    =~ s/\%\{REQUEST_URI\}/\//g if length $url;
        $status =~ s/\%\{REQUEST_URI\}/\//g;
        my $data = {
            'domain'                => $fulldomain,
            'reldir'                => $reldir,
            'basedir'               => $basedir,
            'dir'                   => $dir,
            'status'                => $status,
            'domainkey'             => $sd,
            'subdomain'             => $subdomain,
            'rootdomain'            => $rootdomain,
            'web_subdomain_aliases' => [ Cpanel::WebVhosts::Aliases::get_builtin_alias_subdomains( ($fulldomain) x 2 ) ],
        };

        if ( $OPTS{'return_https_redirect_status'} ) {

            #Then I need to set can_https_redirect and is_https_redirecting
            Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::HttpsRedirect');
            Cpanel::HttpUtils::HttpsRedirect::get_userdata_with_https_redirect_info( $fulldomain, $Cpanel::user, $data );
        }

        push( @RSD, $data );
    }
    save_rewriteinfo_cache();

    return \@RSD;
}

sub load_rewriteinfo_cache {
    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::Htaccess');
    return if $Cpanel::HttpUtils::Htaccess::rewrite_cache_loaded;

    my $path = _REWRITE_INFO_CACHE_PATH();

    if ( -r $path ) {
        $Cpanel::Debug::level >= 5 && print STDERR "Loading rewriteinfo cache from “$path”\n";
        my $cache_mtime = ( stat(_) )[9];
        return if ( $cache_mtime + ( 60 * 86400 ) < time() );    #expire old entries after 60 days

        if ( open( my $cache_fh, '<', $path ) ) {
            eval {
                local $SIG{__DIE__};
                local $SIG{__WARN__};
                $Cpanel::HttpUtils::Htaccess::rewrite_cache_ref = Cpanel::AdminBin::Serializer::LoadFile($cache_fh);
                if ( ref $Cpanel::HttpUtils::Htaccess::rewrite_cache_ref && $Cpanel::HttpUtils::Htaccess::rewrite_cache_ref->{'VERSION'} && $Cpanel::HttpUtils::Htaccess::rewrite_cache_ref->{'VERSION'} == $VERSION ) {
                    $Cpanel::HttpUtils::Htaccess::rewrite_cache_loaded = 1;
                }
                else {
                    $Cpanel::HttpUtils::Htaccess::rewrite_cache_ref = undef;
                }
            };
            close($cache_fh);
        }
        else {
            warn "Failed to open “$path”: $!";
        }
    }
    elsif ( !$!{'ENOENT'} ) {
        warn "Cannot read “$path”: $!";
    }

    return;
}

sub save_rewriteinfo_cache {
    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::Htaccess');
    if ( $Cpanel::homedir && $Cpanel::HttpUtils::Htaccess::rewrite_cache_changed ) {
        my $path = _REWRITE_INFO_CACHE_PATH();
        my ($dir) = $path =~ m<\A(.+)/>;

        if ( !-e $dir ) {
            Cpanel::SafeDir::MK::safemkdir( $dir, '0700' );
        }
        $Cpanel::HttpUtils::Htaccess::rewrite_cache_ref->{'VERSION'} = $VERSION;
        Cpanel::FileUtils::Write::overwrite( $path, Cpanel::AdminBin::Serializer::Dump($Cpanel::HttpUtils::Htaccess::rewrite_cache_ref), 0600 );
    }

    return;
}

1;
