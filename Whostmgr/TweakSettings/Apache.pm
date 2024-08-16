package Whostmgr::TweakSettings::Apache;

# cpanel - Whostmgr/TweakSettings/Apache.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::WebServer                    ();
use Cpanel::ConfigFiles::Apache::modules ();
use Cpanel::HttpUtils::Version           ();
use Cpanel::Imports;
use Cpanel::Locale             ();
use Cpanel::Config::Httpd::EA4 ();
use Cpanel::EA4::Conf::Tiny    ();

=encoding utf-8

=head1 NAME

Whostmgr::TweakSettings::Apache - The Apache namespaced TweakSettings module

=head1 SYNOPSIS

    use Whostmgr::TweakSettings ();

    my $default_tweaksetting_info = Whostmgr::TweakSettings::get_conf('Apache');

=head1 DESCRIPTION

This module is used by the TweakSettings system to get the defaults for and process settings for the Apache TweakSettings namespace.

=cut

sub _is_whole_number {    #integers >= 0
    my $val = shift() // "";

    return $val =~ m{\A\d+\z}
      ? int $val
      : ();
}

sub _is_natural_number {    #integers >= 1
    my $val = shift();

    return ( $val && $val =~ m{\A\d+\z} )
      ? int $val
      : ();
}

our %Conf;
our @Display;
our $APACHE_VERSION;
our $APACHE_URI_VERSION;
our $APACHE_1_3;
our $httpd_dash_uppercase_v_hr;
our $HAS_HARD_LIMIT_PATCH;
our $HARD_SERVER_LIMIT;

my $_did_init_vars = 0;

sub init {
    require Perl::Phase;
    Perl::Phase::assert_is_run_time();
    _init_vars() if !$_did_init_vars++;
    return;
}
our $ea4cnf;

sub _init_vars {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix

    $ea4cnf ||= { Cpanel::EA4::Conf::Tiny::DEFAULTS_filled_in() };

    my $use_safe_default = $ENV{'CPANEL_BASE_INSTALL'};

    $APACHE_VERSION     = Cpanel::HttpUtils::Version::get_httpd_version()              || ( $use_safe_default ? 2.4 : 0 );
    $APACHE_URI_VERSION = Cpanel::HttpUtils::Version::get_current_apache_uri_version() || ( $use_safe_default ? 2.4 : 0 );
    $APACHE_1_3         = $APACHE_URI_VERSION =~ m{\A1\.3};
    my $short_version = Cpanel::ConfigFiles::Apache::modules::apache_short_version() || ( $use_safe_default ? 2 : 0 );

    my $is_ea4 = Cpanel::Config::Httpd::EA4::is_ea4();

    $httpd_dash_uppercase_v_hr = Cpanel::ConfigFiles::Apache::modules::get_options_support();
    $HAS_HARD_LIMIT_PATCH      = exists $httpd_dash_uppercase_v_hr->{'HARD_SERVER_LIMIT'} && int( $httpd_dash_uppercase_v_hr->{'HARD_SERVER_LIMIT'} ) != 256 ? 1 : 0;

    $HARD_SERVER_LIMIT = $APACHE_VERSION =~ m/^2/ ? 'ServerLimit' : ( $HAS_HARD_LIMIT_PATCH ? 2048 : 256 );

    my $logformat_help = qq{<p>Warning: do not change this unless you know the impact of doing so. Stats may be wrong if you set this improperly.</p>[<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/mod_log_config.html#logformat">More Info</a>]};

    %Conf = (
        fileetag => {
            type    => 'select',
            options => [ qw(All None), 'INode MTime', 'INode Size', 'MTime Size', qw(INode MTime Size) ],
            default => $ea4cnf->{fileetag},
            pci     => 'None',
            label   => 'File ETag',
            help    => qq{<p>This directive configures the file attributes that are used to create the <a href="http://en.wikipedia.org/wiki/HTTP_ETag" target="_blank">ETag</a> response header field when the request is file based.</p>
           <p>Note: “None” means that if a document is file based, no ETag field will be included in the response.</p>
           [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#fileetag">More Info</a>]},
        },
        keepalive => {
            type    => 'binary',
            default => $ea4cnf->{keepalive},
            format  => sub {
                my $val = shift;
                return ( defined $val && ( $val eq 'On' || $val eq 1 ) ? 1 : 0 );
            },
            checkval => sub { shift() ? 'On' : 'Off' },
            label    => 'Keep-Alive',
            help     => qq{<p>This directive enables persistent HTTP connections.</p>
            [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#keepalive">More Info</a>]}
        },
        keepalivetimeout => {
            type     => 'text',
            default  => $ea4cnf->{keepalivetimeout},
            checkval => \&_is_whole_number,
            label    => 'Keep-Alive Timeout',
            help     => qq{<p>This directive sets the amount of time the server will wait for subsequent requests on a persistent connection.</p>
            [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#keepalivetimeout">More Info</a>]}
        },
        loglevel => {
            type    => 'select',
            options => [qw( emerg alert crit error warn notice info debug)],
            default => $ea4cnf->{loglevel},
            label   => 'LogLevel',
            help    => qq{<p>This directive adjusts the verbosity of the messages recorded in the error logs. Values below 'info' are <b>not recommended</b> for production systems.</p>
            [<a target="_blank" href="https://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#loglevel">More Info</a>]},
        },
        minspareservers => {
            type     => 'text',
            default  => $ea4cnf->{minspareservers},
            checkval => \&_is_whole_number,
            label    => 'Minimum Spare Servers',
            help     => qq{<p>This directive sets the desired minimum number of idle child server processes. Tuning of this parameter should only be necessary on very busy sites.</p>
            [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/}
              . ( $APACHE_1_3 ? 'core.html' : 'prefork.html' ) . q{#minspareservers">More Info</a>]},
        },
        logformat_combined => {
            type     => 'text',
            default  => $ea4cnf->{logformat_combined},
            checkval => sub {
                $_[0] //= "";
                return if $_[0] =~ m/[\n\r]/;
                return if $_[0] =~ m/(?<!\\)"/;    # blatently unescaped "
                for my $match ( $_[0] =~ m/([\\]+)"/g ) {
                    my @slashes = split( //, $match );
                    return if @slashes % 2 == 0;    # unesacaped " by virtue of an even number of slashes. \" ok, \\" bad, \\\" ok, \\\\" bad, ad infinitum
                }
                return $_[0];
            },
            label => "LogFormat (combined)",
            help  => $logformat_help,

        },
        logformat_common => {
            type     => 'text',
            default  => $ea4cnf->{logformat_common},
            checkval => sub {
                return if !$_[0] || $_[0] =~ m/[\n\r]/;
                return if $_[0]           =~ m/(?<!\\)"/;    # blatently unescaped "
                for my $match ( $_[0] =~ m/([\\]+)"/g ) {
                    my @slashes = split( //, $match );
                    return if @slashes % 2 == 0;             # unesacaped " by virtue of an even number of slashes. \" ok, \\" bad, \\\" ok, \\\\" bad, ad infinitum
                }
                return $_[0];
            },
            label => "LogFormat (common)",
            help  => $logformat_help,
        },
        maxclients => {
            type     => 'text',
            default  => $ea4cnf->{maxclients},
            checkval => sub {                    #parameters: value, config hash
                return if !_is_whole_number( $_[0] );

                my $limit = $HAS_HARD_LIMIT_PATCH ? 2048 : 256;

                if ( $short_version == 2 ) {
                    $limit = 20_000;    #check against serverlimit in post_process()
                }

                return $_[0] <= $limit ? $_[0] : ();
            },
            label => eval { $APACHE_URI_VERSION >= 2.4 ? 'Max Request Workers' : 'Max Clients'; },
            ( $HARD_SERVER_LIMIT =~ m{\D} ? () : ( 'maximum' => $HARD_SERVER_LIMIT ) ),
            help => eval {
                my ( $module, $directive, $xtra );

                if ($APACHE_1_3) {
                    $module    = 'core';
                    $directive = 'MaxClients';
                    $xtra      = q{that can be supported.};

                    if ( $HARD_SERVER_LIMIT =~ /256/ ) {
                        $xtra .= q{</p><p>The EasyApache “Raise Hard Server Limit” option for Apache 1.3 raises the maximum to 2,048.};
                    }
                }
                else {
                    $module = 'mpm_common';
                    $xtra   = q{that will be served. This interface allows up to the value of the ServerLimit setting.};

                    if ( $APACHE_URI_VERSION >= 2.4 ) {
                        $xtra .= q{ This used to be called 'MaxClients' prior to Apache 2.4.};
                        $directive = 'MaxRequestWorkers';
                    }
                    else {
                        $directive = 'MaxClients';
                    }
                }

                my $url = Cpanel::ConfigFiles::Apache::modules::get_module_url( $APACHE_URI_VERSION, $module, $directive );

                # generated help string
                qq{<p>This directive sets the limit on the number of simultaneous requests $xtra</p>} . qq{[<a target="_blank" href="$url">More Info</a>]};
            },
        },
        maxkeepaliverequests => {
            type      => 'text',
            default   => $ea4cnf->{maxkeepaliverequests},
            can_undef => "Unlimited",                       # “Unlimited” is just a true-thy value indicating its meaning, its not actually used as a value
            checkval  => \&_is_natural_number,
            format    => sub {
                my $val = shift;

                if ( defined $val ) {
                    if ( length($val) == 0 || $val == 0 ) {
                        return undef;
                    }
                }

                return $val;
            },
            label => 'Max Keep-Alive Requests',
            help  => qq{<p>This directive sets the number of requests allowed on a persistent connection.</p>
            [<a target="_blank" href="https://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#maxkeepaliverequests">More Info</a>]},
        },
        maxrequestsperchild => {
            type     => 'text',
            default  => $ea4cnf->{maxrequestsperchild},
            checkval => \&_is_whole_number,
            label    => eval { $APACHE_URI_VERSION >= 2.4 ? 'Max Connections Per Child' : 'Max Requests Per Child'; },
            help     => eval {
                my ( $module, $directive, $xtra );

                if ( $APACHE_URI_VERSION >= 2.4 ) {
                    $module    = 'mpm_common';
                    $directive = 'MaxConnectionsPerChild';
                    $xtra      = " This used to be called 'MaxRequestsPerChild' prior to Apache 2.4.";
                }
                else {
                    $module    = 'core';
                    $directive = 'MaxRequestsPerChild';
                    $xtra      = '';
                }

                my $url = Cpanel::ConfigFiles::Apache::modules::get_module_url( $APACHE_URI_VERSION, $module, $directive );

                # the resulting help string
                qq{<p>This directive sets the limit on the number of requests that an individual child server process will handle.</p>
                <p>After $directive requests, the child process will die. If $directive is 0, then the process will never expire.$xtra</p>
                [<a target="_blank" href="$url">More Info</a>]};
            },
        },
        maxspareservers => {
            type     => 'text',
            default  => $ea4cnf->{maxspareservers},
            checkval => \&_is_whole_number,
            label    => 'Maximum Spare Servers',
            help     => qq{<p>This directive sets the desired maximum number of idle child server processes. Tuning of this parameter should only be necessary on very busy sites.</p>
            [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/}
              . ( $APACHE_1_3 ? 'core.html' : 'prefork.html' ) . q{#maxspareservers">More Info</a>]},
        },
        root_options => {
            type     => 'multiselect',
            options  => [qw(ExecCGI FollowSymLinks Includes IncludesNOEXEC Indexes MultiViews SymLinksIfOwnerMatch)],
            checkval => sub {
                my ($vals_ar) = @_;
                $vals_ar = [] if !$vals_ar || ( ref $vals_ar ne 'ARRAY' && ref $vals_ar ne 'HASH' );
                my %vals;
                if ( ref $vals_ar eq 'ARRAY' ) {
                    %vals = map { $_ => 1 } @$vals_ar;
                }
                else {
                    %vals = %$vals_ar;
                }
                if ( $vals{'FollowSymLinks'} || $vals{'SymLinksIfOwnerMatch'} ) {
                    return $vals_ar;
                }
                else {
                    return ( undef, 'At least one of the two options must be selected:  FollowSymLinks, SymLinksIfOwnerMatch' );
                }
            },
            default => { map { $_ => 1 } split /\s+/, $ea4cnf->{root_options} },
            label   => "Directory “/” Options",
            help    => qq{<p>This directive’s values enable or disable various features of Apache. It is recommended that you thoroughly read the documentation before changing any of its values to avoid inadvertently disabling features on which your customers may rely.</p>
           <p>Note: These settings can be overridden in other contexts that have their own Options directive.</p>
           [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#options">More Info</a>]},
        },
        (
            $APACHE_1_3 ? () : (
                'serverlimit' => {
                    type     => 'text',
                    default  => $ea4cnf->{serverlimit},
                    checkval => $short_version == 1 ? sub { shift } : \&_is_whole_number,
                    maximum  => $short_version == 1 ? undef         : 20_000,
                    label    => 'Server Limit',
                    help     => qq{<p>This directive sets the maximum configured value for MaxClients for the lifetime of the Apache process.</p>
           <p>Special care must be taken when using this directive. If ServerLimit is set to a value much higher than necessary, extra, unused shared memory will be allocated. If both ServerLimit and MaxClients are set to values higher than the system can handle, Apache may not start or the system may become unstable.</p>
           <p>We highly recommend using the default setting unless you fully understand how it will interact with your Apache build and MaxClients setting.</p>
           [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/mpm_common.html#serverlimit">More Info</a>]},
                }
            )
        ),
        serversignature => {
            type    => 'select',
            options => [qw(On Off Email)],
            default => $ea4cnf->{serversignature},
            pci     => 'Off',
            label   => 'Server Signature',
            help    => qq{<p>This “signature” is the trailing footer line under server-generated documents (error messages, information pages, etc).</p>
           [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#serversignature">More Info</a>]},
        },
        servertokens => {
            type         => 'select',
            options      => [qw(ProductOnly Minimal OS Full)],
            optionlabels => { ProductOnly => 'Product Only' },
            default      => $ea4cnf->{servertokens},
            pci          => 'ProductOnly',
            label        => 'Server Tokens',
            help         => qq{This controls whether a “Server” response header field is sent back to clients, and if so what level of detail is included.
<ul>
    <li>Product Only (e.g. “Apache”)</li>
    <li>Minimal (e.g Apache/$APACHE_VERSION)</li>
    <li>OS (e.g Apache/$APACHE_VERSION (Unix))</li>
    <li>Full (e.g Apache/$APACHE_VERSION (Unix) MyModX/1.3 MyModY/1.4)</li>
</ul>
    [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#servertokens">More Info</a>]},
        },
        sslciphersuite => {
            type     => 'text',
            default  => $ea4cnf->{sslciphersuite},
            checkval => sub {
                return if !length $_[0] || $_[0] =~ m{\s};
                return $_[0];
            },
            label => 'SSL Cipher Suite',
            help  => qq{<p>This complex directive uses a colon-separated “cipher-spec” string consisting of OpenSSL cipher specifications to configure the cipher suite that the client negotiates in the SSL handshake phase.</p>
           <p>Note: This is the global SSLCipherSuite setting. You can also set SSLCipherSuite in other contexts (for example, a VirtualHost). In that context, it would override the global setting. This can cause PCI scans to fail port 443 even if SSLCipherSuite is set appropriately in this interface. For information on how to check for that situation and address it, <a target="_blank" href="https://go.cpanel.net/pciinfo">click here</a>.</p>},
        },
        sslprotocol => {
            type     => 'text',
            default  => $ea4cnf->{sslprotocol},
            checkval => sub {
                return if !$_[0];

                require Cpanel::SSL::Defaults;
                my $ea4_proto = Cpanel::SSL::Defaults::ea4_all_protos();
                my %protocols = ( all => 1, map { lc($_) => $ea4_proto->{$_} } keys %{$ea4_proto} );
                foreach my $proto ( split / /, $_[0] ) {
                    return if !( $proto =~ m/^[+-]?(.+)$/ && exists $protocols{ lc $1 } );
                }

                {
                    local $@;
                    my @banned_versions = eval { Cpanel::SSL::Defaults::has_banned_TLS_protocols( $_[0] ) };
                    if ( my $excep = $@ ) {
                        require Cpanel::Debug;
                        Cpanel::Debug::log_info($excep);
                        return;
                    }
                    return if @banned_versions;
                }

                return $_[0];
            },
            label => 'SSL/TLS Protocols',
            help  => qq{<p>This complex directive uses a space-separated string consisting of protocol specifications to configure the SSL and TLS protocols that the client and server negotiate in the SSL/TLS handshake phase.</p>
           <p>Note: This is the global SSLProtocol setting. You can also set SSLProtocol in other contexts (for example, a VirtualHost). In that context, it would override the global setting. This can cause PCI scans to fail port 443 even if SSLProtocol is set appropriately in this interface.</p><p class="alert alert-warning">To ensure compatibility with all clients, we recommend that you enable <code>TLSv1.2</code>.</p>},
        },
        sslusestapling => {
            type    => 'binary',
            default => $ea4cnf->{sslusestapling},
            format  => sub {
                my $val = shift;
                return ( defined $val && ( $val eq 'On' || $val eq 1 ) ? 1 : 0 );
            },
            checkval => sub { shift() ? 'On' : 'Off' },
            label    => 'SSL Use Stapling',
            help     => "<p>This option enables OCSP stapling. If enabled (and requested by the client), an OCSP response for its own certificate will be included in the TLS handshake.</p>",
        },
        extendedstatus => {
            type    => 'binary',
            default => $ea4cnf->{extendedstatus},
            format  => sub {
                my $val = shift;
                return ( defined $val && ( $val eq 'On' || $val eq 1 ) ? 1 : 0 );
            },
            checkval => sub { shift() ? 'On' : 'Off' },
            label    => 'Extended Status',
            help     => "<p>This directive enables the display of additional information about incoming requests on the Apache status page.</p>",
        },
        startservers => {
            type     => 'text',
            default  => $ea4cnf->{startservers},
            checkval => \&_is_whole_number,
            label    => 'Start Servers',
            help     => qq{<p>This directive sets the number of child server processes created on startup. Since the number of processes is dynamically controlled depending on the load, there is usually little reason to adjust this parameter.</p>
        [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/}
              . ( $APACHE_1_3 ? 'core.html' : 'mpm_common.html' ) . q{#startservers">More Info</a>]},
        },
        timeout => {
            type     => 'text',
            default  => $ea4cnf->{timeout},
            checkval => sub {
                my ($val) = @_;
                return if !_is_whole_number($val);
                return if $val < 3;                  # 1% of default seems reasonable, if we start seeing valid use cases of less than 3 we can update it/make it configurable/etc. for now though YAGNI
                return if $val > 604800;             #  to prevent very large numbers from getting stringified into exponent format. If your request takes over a week you have way bigger problems than not being able to enter a higher number here …
                return $val;
            },
            label => 'Timeout',
            help  => qq{<p>This directive sets the amount of time the server will wait for certain events before failing a request.</p>
           [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#timeout">More Info</a>]},
        },
        traceenable => {
            type    => 'select',
            options => [qw(On Off Extended)],
            default => $ea4cnf->{traceenable},
            pci     => 'Off',
            label   => 'Trace Enable',
            help    => qq{<p>This directive sets the behavior of TRACE requests for both the core server and mod_proxy.</p>
           [<a target="_blank" href="http://httpd.apache.org/docs/$APACHE_URI_VERSION/mod/core.html#traceenable">More Info</a>]},
        },
    );

    @Display = (
        [
            'Apache Configuration' => [
                qw(
                  sslciphersuite
                  sslprotocol
                  sslusestapling
                  extendedstatus
                  loglevel
                ),
                ( $is_ea4 ? qw(logformat_combined logformat_common) : () ),
                qw(traceenable
                  serversignature
                  servertokens
                  fileetag
                  root_options
                  startservers
                  minspareservers
                  maxspareservers
                ),
                $APACHE_1_3 ? () : 'serverlimit',
                qw(
                  maxclients
                  maxrequestsperchild
                  keepalive
                  keepalivetimeout
                  maxkeepaliverequests
                  timeout
                )
            ]
        ],
    );

    # TODO: Deal with the custom directive support being removed and the option
    # remaining in the local config file.
    my $apache = Cpanel::WebServer->new()->get_server( type => 'apache' );
    if ( $apache->is_directive_supported('SymlinkProtect') ) {
        $Conf{symlink_protect} = {
            type    => 'binary',
            default => $ea4cnf->{symlink_protect},
            format  => sub {
                my $val = shift;
                return ( defined $val && ( $val eq 'On' || $val eq 1 ) ? 1 : 0 );
            },
            checkval => sub { shift() ? 'On' : 'Off' },
            label    => 'Symlink Protection',
            help     => qq{<p>This directive enables symlink protection in order to reduce the impact of race conditions if you enable the FollowSymlinks and SymLinksIfOwnerMatch Apache directives.</p>
            <p>If one or both of those directives are not in effect this directive will have unexpected behavior so it is highly recommended to leave it off in that case.</p>
            <p>The checks this directive performs can have significant performance impacts on the server. We strongly recommend that you do not enable this feature unless you absolutely require it.</p>
            [<a target="_blank" href="https://go.cpanel.net/EA4Symlink">More Info</a>]},
        };

        push @{ $Display[0]->[1] }, 'symlink_protect';
    }

    return;
}    # _init_vars

# Here we check maxclients against serverlimit && sslciphersuite against sslprotocol
sub post_process {
    my ( $in_h, $new_h, $rej_h, $rejr_h ) = @_;

    return if $APACHE_1_3;

    if ( exists $new_h->{'maxclients'} && exists $new_h->{'serverlimit'} ) {
        my $mc_is_valid;
        my $server_limit;
        if ( Cpanel::ConfigFiles::Apache::modules::apache_mpm_threaded() ) {
            my $threads_per_child = ( exists $new_h->{'threadsperchild'} ) ? $new_h->{'threadsperchild'} : $ea4cnf->{threadsperchild};
            $server_limit = int( abs $new_h->{'serverlimit'} * $threads_per_child );
            $mc_is_valid  = $new_h->{'maxclients'} <= $server_limit;
        }
        else {
            $server_limit = int( abs $new_h->{'serverlimit'} );
            $mc_is_valid  = $new_h->{'maxclients'} <= $server_limit;
        }
        if ( !$mc_is_valid ) {
            $rej_h->{'maxclients'}  = delete $new_h->{'maxclients'};
            $rejr_h->{'maxclients'} = Cpanel::Locale->get_handle()->maketext( '“[_1]” must be less than or equal to “[_2]”.', 'maxclients', $server_limit );
        }
    }

    my $sslprotocol_changed    = _value_changed( 'sslprotocol',    $in_h, $new_h );
    my $sslciphersuite_changed = _value_changed( 'sslciphersuite', $in_h, $new_h );

    if ( $sslprotocol_changed || $sslciphersuite_changed ) {
        require Cpanel::EA4::Conf;
        my $e4c = Cpanel::EA4::Conf->new;

        my $cipher_key = 'sslciphersuite_other';
        my $proto_key  = 'sslprotocol_other';

        if ( $sslprotocol_changed && !$sslciphersuite_changed ) {
            $cipher_key = '___original_sslciphersuite';
        }
        elsif ( !$sslprotocol_changed && $sslciphersuite_changed ) {
            $proto_key = '___original_sslprotocol';

            # if they are set to default allow it to be adjusted to fit the new sslprotocol
            #    (e.g. adding TLSv1.3 will be the default plus TLSv1.3 ciphers)
            return if defined $sslciphersuite_changed && $sslciphersuite_changed eq $ea4cnf->{sslciphersuite};
        }

        my $sslprotocol    = $sslprotocol_changed    || $in_h->{$proto_key};
        my $sslciphersuite = $sslciphersuite_changed || $in_h->{$cipher_key};
        $e4c->sslprotocol($sslprotocol);
        $e4c->sslciphersuite($sslciphersuite);

        my $norm_sslciphersuite_new = join( ":", sort split( /:/, $sslciphersuite ) );
        my $norm_sslciphersuite_obj = join( ":", sort split( /:/, $e4c->sslciphersuite ) );

        if ( $norm_sslciphersuite_new ne $norm_sslciphersuite_obj ) {
            $rej_h->{sslciphersuite} = $sslciphersuite;
            delete $new_h->{sslciphersuite};
        }
    }

    return;
}

sub _value_changed {
    my ( $key, $in_h, $new_h ) = @_;

    my $other = $key . "_other";
    my $orig  = "___original_$key";

    if ( defined $in_h->{$other} ) {
        return $in_h->{$other} if $in_h->{$other} ne $in_h->{$orig};
        return;    # in case a value can be 0 or ""
    }
    elsif ( defined $new_h->{$key} ) {
        return $new_h->{$key} if $new_h->{$key} ne $in_h->{$orig};
        return;    # in case a value can be 0 or ""
    }

    # this should never happen, how did we get here?
    warn "“$key” was not in data stucture as expected\n";
    return;
}

1;
