package Cpanel::Template::Plugin::Apache;

# cpanel - Cpanel/Template/Plugin/Apache.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This functionality isn't necessarily specific to Apache, but it's
#definitely stuff that templates shouldn't be doing normally.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(Template::Plugin);

use Cpanel::ApacheConf::ModRewrite::Utils ();
use Cpanel::IP::Parse                     ();
use Cpanel::Config::LoadConfig            ();
use Cpanel::WebVhosts::AutoDomains        ();
use Cpanel::ApacheConf::DCV               ();

my $DCV_PATTERNS;

my %PROXY_SUBDOMAIN_REDIRECT_RULE           = Cpanel::WebVhosts::AutoDomains::PROXY_SUBDOMAIN_REDIRECTS_KV();
my %PROXY_SUBDOMAIN_WEBSOCKET_REDIRECT_RULE = Cpanel::WebVhosts::AutoDomains::PROXY_SUBDOMAIN_WEBSOCKET_REDIRECTS_KV();

#Don't bother creating these as plugin methods because:
#   1) Longstanding use is for these to be directly in the stash.
#   2) It's slower to access these as plugin methods than as stash members.
my %stash_extensions;

sub setup_stash {
    return (

        #Tells the Apache templates to enable the 11.64+ mode of redirecting
        #SSL service (formerly proxy) subdomains to non-SSL internal URLs.
        ssl_proxy_to_non_ssl => 1,

        supports_cpanelwebcall => 1,

        proxypass_for_proxysubdomains         => 1,
        'all_possible_proxy_subdomains_regex' => \&Cpanel::WebVhosts::AutoDomains::all_possible_proxy_subdomains_regex,

        # This is hard coded since we always have it enabled.
        # We cannot remove it because the EA4 templates come in
        # rpm which cannot be updated until we stop supported versions
        # that do not have it forced on.
        'global_dcv_rewrite_exclude' => 1,

        proxy_subdomain_redirect_rule                     => \&proxy_subdomain_redirect_rule,
        proxy_subdomain_websocket_redirect_rule_if_exists => \&proxy_subdomain_websocket_redirect_rule_if_exists,

        dcv_rewrite_patterns      => sub { return ( $DCV_PATTERNS ||= [ Cpanel::ApacheConf::DCV::get_patterns() ] ) },
        fglob                     => \&file_count,
        cachedfglob               => \&cached_file_count,
        file_test                 => \&do_file_test,
        parsed_ip                 => \&parsed_ip,
        has_ocsp                  => \&certificate_has_ocsp,
        mod_rewrite_string_escape => \&Cpanel::ApacheConf::ModRewrite::Utils::escape_for_stringify,
        load_conf                 => sub {
            my $conf = {};
            Cpanel::Config::LoadConfig::loadConfig( shift, $conf );    # need JSON or YAML? Add logic for that here!
            return $conf;
        },
    );

    return;
}

sub proxy_subdomain_redirect_rule {
    my ($proxy_sub_label) = @_;

    return $PROXY_SUBDOMAIN_REDIRECT_RULE{$proxy_sub_label} || do {
        die "Unrecognized service subdomain for redirect: “$proxy_sub_label”";
    };
}

sub proxy_subdomain_websocket_redirect_rule_if_exists {
    my ($proxy_sub_label) = @_;

    return $PROXY_SUBDOMAIN_WEBSOCKET_REDIRECT_RULE{$proxy_sub_label};
}

sub parsed_ip {
    my $ip_port = shift;
    my ( $version, $ip, $port ) = Cpanel::IP::Parse::parse( $ip_port, undef, $Cpanel::IP::Parse::BRACKET_IPV6 );
    return $ip;
}

=head1 C<< certificate_has_ocsp($cert_file) >>

Determines whether the supplied certificate contains OCSP data.  This
will be used within the Apache configuration templates; a false return
will turn off stapling for the given domain, to prevent spurious error
messages in the Apache error log on startup.

=over 4

=item C<$cert_file> [in]

A filename which should contain an X509 SSL certificate.

=back

B<Returns:> truth value (0 or 1) of the presence of OCSP data.

=cut

sub certificate_has_ocsp {
    my ($cert_file) = @_;
    my $cert_obj;
    require Cpanel::SSL::Objects::Certificate::File;
    eval { $cert_obj = Cpanel::SSL::Objects::Certificate::File->new( 'path' => $cert_file ); };
    return 0 if !$cert_obj;
    return $cert_obj->OCSP() ? 1 : 0;
}

sub load {
    my ( $class, $context ) = @_;
    my $stash = $context->stash();

    %stash_extensions = setup_stash();

    @{$stash}{ keys %stash_extensions } = values %stash_extensions;

    #Not sure this is ever needed, but..
    clear_glob_cache();

    clear_file_test_cache();

    return $class;
}

# from Cpanel::AdvConfig::apache::filesys
#### This chunk of filesys.pm is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##

my $cached_glob_ref;

my $_real_file_glob_cr;

our %GLOB_CACHE;
our $KEEP_GLOB_CACHE      = 0;
our $KEEP_FILE_TEST_CACHE = 0;

my %file_test_cache;

#Ordered parameters:
#   0: the file test to be done
#   1: the path to check
#   2: a flag to disregard the cache
#
#NOTE: This can be called 1,000s of times when rebuilding httpd.conf,
#so read @_ directly for speed.
sub do_file_test {
    return undef if length( $_[0] ) != 1 || $_[1] =~ tr/';//;

    #There probably aren't many instances of disregarding the cache,
    #so the end cost of the string eval here is negligible. Were that ever
    #different, we may want to cache the string eval.
    if ( $_[2] || !exists $file_test_cache{ $_[0] }{ $_[1] } ) {
        $file_test_cache{ $_[0] }{ $_[1] } = eval qq{-$_[0] '$_[1]';} ? 1 : 0;    ##no critic qw(ProhibitStringyEval)
    }

    return $file_test_cache{ $_[0] }{ $_[1] };
}

#TODO: What the templates actually need to know is dir_has_files(), not
#the actual number of files.
sub file_count {

    # eval is assumedly necessary to keep binaries from getting errors about loading File::Glob
    $_real_file_glob_cr ||= eval 'sub { return scalar @{ [ glob($_[0]) ] } ; }';    ##no critic qw(ProhibitStringyEval)

    return $_real_file_glob_cr->(@_);
}

#NOTE: This can be called 1,000s of times when rebuilding httpd.conf,
#so read @_ directly for speed.
sub cached_file_count {

    #eval is assumedly necessary to keep binaries from getting errors about loading File::Glob
    $cached_glob_ref ||= eval 'sub { return [ glob($_[0]) ]; }';    ##no critic qw(ProhibitStringyEval)

    $GLOB_CACHE{ $_[0] } ||= $cached_glob_ref->( $_[0] );

    return scalar @{ $GLOB_CACHE{ $_[0] } };
}

sub clear_glob_cache {
    if ( !$KEEP_GLOB_CACHE ) {
        %GLOB_CACHE = ();
    }

    return;
}

sub clear_file_test_cache {
    if ( !$KEEP_FILE_TEST_CACHE ) {
        %file_test_cache = ();
    }

    return;
}

# /Cpanel::AdvConfig::apache::filesys
1;
