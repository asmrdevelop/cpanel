package Cpanel::SSL::DCV;

# cpanel - Cpanel/SSL/DCV.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV

=head1 SYNOPSIS

    #Does a recursive DNS lookup on the domain for extra assurance.
    my $result_hr = Cpanel::SSL::DCV::verify_http(
        'http://domain.com/url/to/load',
        'expected payload',
        'optional user agent string',
    );

    #This is important to coordinate with external DCV providers.
    if ( $result_hr->{'redirects_count'} ) { ... }

    #Returns a list of problems as hashes for the associated
    #(same-order) domain. So, in the below example, we’d get something like:
    #(
    #   {
    #       failure_reason => 'This is a problem.',
    #       redirects_count => 0,
    #       lacks_docroot => ...,
    #   },
    #   {
    #       failure_reason => undef,    #i.e., succeeded
    #       redirects_count => 1,
    #       lacks_docroot => ...,
    #   },
    #)
    my @problems = Cpanel::SSL::DCV::verify_domains(
        domains => [
            'bad.org',
            'good.net',
        ],
    );

=head1 DESCRIPTION

This module includes logic for HTTP-based DCV. If you need DNS-based
DCV, look at L<Cpanel::SSL::DCV::DNS>.

This module will, if development mocking is enabled, fail DCV for
any domain that has the letters C<badhttp> in it.

=cut

use cPstrict;

use Try::Tiny;

use URI::Split ();

use Cpanel::Autodie              ();
use Cpanel::Context              ();
use Cpanel::KnownProxies         ();
use Cpanel::DnsRoots             ();
use Cpanel::Exception            ();
use Cpanel::Finally              ();
use Cpanel::Fcntl                ();
use Cpanel::HTTP::Client         ();
use Cpanel::IP::LocalCheck       ();
use Cpanel::IP::Loopback         ();
use Cpanel::IP::Utils            ();
use Cpanel::LoadModule           ();
use Cpanel::Logger               ();
use Cpanel::NAT                  ();
use Cpanel::WildcardDomain       ();
use Cpanel::WildcardDomain::Tiny ();
use Cpanel::Rand::Get            ();
use Cpanel::Security::Authz      ();
use Cpanel::WebVhosts            ();

use Cpanel::SSL::DCV::Ballot169::Constants ();

my $_dns_roots;    # reuse the cache between domains if possible
END { undef $_dns_roots }

use constant {

    #Really, even a large DCV response should be smaller than
    #1 KiB; however, we want to allow larger sizes in the event
    #that having more of the response might be useful in tracking
    #down overactive redirections, etc.
    MAX_SIZE => 16384,
};

our $_DEBUG                                   = 0;
our $MAX_TEMP_FILE_CREATION_ATTEMPTS          = 50;
our $MAX_HTTP_CONNECT_TIMEOUT                 = 5;                        # DCV should mostly be local
our $MAX_HTTP_READ_TIMEOUT                    = 10;                       # DCV should mostly be local
our $DEFAULT_TEMP_FILE_RANDOM_CHARACTER_COUNT = 100;
our $DEFAULT_TEMP_FILE_RANDOM_CHARACTERS      = [ 'A' .. 'Z', 0 .. 9 ];
our $DEFAULT_TEMP_FILE_EXTENSION              = '';

=head1 FUNCTIONS

=head2 verify_domains( %OPTS )

%OPTS is:

=over

=item C<domains> - An arrayref of FQDNs or wildcard domains.

=item C<dcv_file_relative_path>

=item C<dcv_file_extension>

=item C<dcv_file_random_character_count>

=item C<dcv_file_allowed_characters>

=item C<dcv_user_agent_string>

=item C<dcv_max_redirects>

=back

NOTE: This does B<not> do a domain registration check because AutoSSL
does its own registration check, and it’s not very useful for the TLS Wizard.

=cut

sub verify_domains {
    my (%OPTS) = @_;

    my @domains = @{ $OPTS{'domains'} };

    my @wildcards = grep { Cpanel::WildcardDomain::Tiny::is_wildcard_domain($_) } @domains;
    if (@wildcards) {
        die "CAs no longer accept HTTP DCV for wildcard domains (@wildcards)";
    }

    Cpanel::Security::Authz::verify_not_root();

    Cpanel::Context::must_be_list();

    my @dcved_domains;

    my $dcv_config = _build_and_validate_dcv_config_from_args(%OPTS);

    my $dns_lookups_hr = _dnsroots_obj()->get_ip_addresses_for_domains(@domains);
    foreach my $domain (@domains) {

        my $error;
        my $verify_resp;

        my $lacks_docroot;
        try {
            my $docroot = Cpanel::WebVhosts::get_docroot_for_domain($domain);
            if ( !$docroot ) {
                $lacks_docroot = 1;
                die Cpanel::Exception->create( 'You do not have a document root for the domain “[_1]”.', [$domain] );
            }

            my $rand = Cpanel::Rand::Get::getranddata(64);

            my ( $path, $wfh, $temp_obj ) = _generate_dcv_file_and_get_fh( $dcv_config, $docroot );
            Cpanel::Autodie::chmod( 0644, $wfh );
            Cpanel::Autodie::print( $wfh, $rand );
            Cpanel::Autodie::close($wfh);

            my ($filename) = ( $path =~ m<\A\Q$docroot\E/(.+)> );

            #mocked in tests
            $verify_resp = verify_http_with_dns_lookups( "http://$domain/$filename", $rand, $dcv_config->{'dcv_user_agent_string'}, $dcv_config->{'dcv_max_redirects'}, $dns_lookups_hr );

            $verify_resp->{'failure_reason'} = undef;
        }
        catch {
            my ( $failure_reason, $redirects_count, $redirects );

            # It’s unclear why we would want a debug mode that
            # treats all failures as successes … ?
            if ( !$_DEBUG ) {
                $error = $_;

                if ( try { $error->isa('Cpanel::Exception') } ) {
                    $failure_reason = $error->to_locale_string_no_id();
                }
                else {
                    $failure_reason = Cpanel::Exception::get_string_no_id($error);
                }

                #If this fails then we just have no redirects to report.
                try { $redirects_count = $error->get('redirects_count') };
                try { $redirects       = $error->get('redirects') };
            }

            $verify_resp = {
                redirects_count => $redirects_count,
                failure_reason  => $failure_reason,
                redirects       => $redirects,
            };
        };

        $verify_resp->{'lacks_docroot'} = $lacks_docroot ? 1 : 0;

        push @dcved_domains, $verify_resp;
    }

    return @dcved_domains;
}

my %_cached_down_hosts_errors;
my $_loaded_proxies = 0;

sub verify_http {
    my ( $url, $content, $user_agent_string, $max_redirects ) = @_;
    my $domain = _get_domain_from_url($url);

    my $dns_lookups_hr = _dnsroots_obj()->get_ip_addresses_for_domains($domain);

    return verify_http_with_dns_lookups( $url, $content, $user_agent_string, $max_redirects, $dns_lookups_hr );
}

sub verify_http_with_dns_lookups {
    my ( $url, $content, $user_agent_string, $max_redirects, $dns_lookups_hr ) = @_;

    # We only alter $url here because verify_http() relies on this
    # function for its implementation.
    my $is_mocked = Cpanel::SSL::DCV::Mock->can('is_active');    ## PPI NO PARSE - only needed in dev
    $is_mocked &&= $is_mocked->();
    $url .= '__MADE_TO_FAIL' if $is_mocked && ( -1 != index( $url, 'badhttp' ) );

    my @verify_args = ( $url, $content, $user_agent_string, $max_redirects );

    my $domain = _get_domain_from_url($url);

    if ( my @ipv6 = _get_ipv6_addresses_for_domain( $domain, $dns_lookups_hr ) ) {
        local $@;
        my $ret = eval { _verify_http( @verify_args, 6, \@ipv6 ) };
        return $ret if !$@;
        my $err = $@;

        # If its a proxy that proxies ipv4->ipv6 try fallback
        Cpanel::KnownProxies::reload() if !$_loaded_proxies;
        $_loaded_proxies = 1;
        if ( Cpanel::KnownProxies::is_known_proxy_ipv6_that_forwards_to_ipv4_backend( $ipv6[0] ) ) {
            my @ipv4 = _get_ipv4_addresses_for_domain( $domain, $dns_lookups_hr );
            if ( @ipv4 && Cpanel::KnownProxies::is_known_proxy_ip( $ipv4[0] ) ) {
                return _verify_http( @verify_args, 4, \@ipv4 );
            }
        }

        # Not a proxy -- fail
        local $@ = $err;
        die;

    }
    return _verify_http( @verify_args, 4, [ _get_ipv4_addresses_for_domain( $domain, $dns_lookups_hr ) ] );
}

sub _verify_http {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my ( $url, $content, $user_agent_string, $max_redirects, $ip_version, $ips_ar ) = @_;

    my $domain = _get_domain_from_url($url);

    my $sanity_fetched;

    if ( !@$ips_ar ) {
        die _err_because_no_ips($domain);
    }

    # Ensure the original IP that the domain resolves to is a public IP since the provider will not be able to pass HTTP DCV if it is a private IP
    if ( Cpanel::IP::Utils::get_private_mask_bits_from_ip_address( $ips_ar->[0] ) ) {
        die _err_because_ip_is_private($domain);
    }

    # The IP returned from this may not be locally resolvable if NAT Loopback isn't configured for the host, so we need to check for the Local IP.
    my $test_ip = _get_local_ip( $domain, $ips_ar->[0] );

    my $request_obj;

    my ($original_host) = $url =~ m{://([^/:]+)};
    my ($port)          = $url =~ m{://([^/]+):([0-9]+)/};
    $port ||= 80;

    if ( $_cached_down_hosts_errors{"$test_ip:$port"} ) {
        die Cpanel::Exception->create(
            'The system failed to fetch the [output,abbr,DCV,Domain Control Validation] file at “[output,url,_1]” because of an error (cached): [_2].',
            [ $url, $_cached_down_hosts_errors{"$test_ip:$port"} ],
            { redirects_count => 0 },
        );
    }

    my $peer_coderef = sub {
        my ($host) = @_;

        my @host_addrs;
        if ( $host eq $domain ) {
            @host_addrs = @$ips_ar;
        }
        else {
            @host_addrs = $ip_version == 6 ? _get_ipv6_addresses_for_domain($host) : _get_ipv4_addresses_for_domain($host);
        }
        if ( !@host_addrs ) {
            die _err_because_no_ips($host);
        }

        return _get_local_ip( $host, $host_addrs[0] );
    };

    try {
        $request_obj    = _get_url_request( $url, peer => $peer_coderef, max_redirects => $max_redirects, headers => { length $user_agent_string ? ( 'User-Agent' => $user_agent_string ) : () } );
        $sanity_fetched = $request_obj->content();
    }
    catch {
        # Its possible they have some type of proxy setup so lets try it
        # first and only complain that the ip is not local if it fails
        #

        my $ip_is_local = _ip_is_on_local_server($test_ip) ? 1 : 0;

        my $redirects       = try { $_->get('redirects') } || [];
        my $redirects_count = scalar @$redirects;

        my $final_url = try { $_->get('url') } || $url;

        my $error = try { $_->get('error') };

        if ($error) {

            #see HTTP::Tiny - Could not connect to '$host:$port'
            #Hopefully HTTP::Tiny will give us something more stable
            #to work with than this, but for now this is what we have.
            #cf. https://github.com/chansen/p5-http-tiny/issues/106
            if ( index( $error, 'not connect' ) > -1 ) {
                my ($failed_host_port) = $error =~ m{not connect[^']+'([^']+)};
                my @split_host         = split( m{:}, $failed_host_port );
                my $failed_port        = pop @split_host;
                my $failed_host        = join( ':', @split_host );
                if ( $failed_host eq $original_host && $failed_port eq $port ) {
                    $error =~ s{\Q$failed_host\E:}{$test_ip:};    # Show that it the same ip in future errors
                    $_cached_down_hosts_errors{"$test_ip:$port"} = $error;
                }
            }
        }

        if ( try { $_->isa('Cpanel::Exception::HTTP::Server') } ) {

            if ($ip_is_local) {
                if ( $final_url ne $url ) {
                    die Cpanel::Exception->create(
                        'The system queried for a temporary file at “[output,url,_1]”, which was redirected from “[output,url,_2]”. The web server responded with the following error: [_3] ([_4]). A [output,abbr,DNS,Domain Name System] or web server misconfiguration may exist.',
                        [ $final_url, $url, $_->get('status'), $_->get('reason') ],
                        { redirects_count => $redirects_count, redirects => $redirects },
                    );
                }
                else {
                    die Cpanel::Exception->create(
                        'The system queried for a temporary file at “[output,url,_1]”, but the web server responded with the following error: [_2] ([_3]). A [output,abbr,DNS,Domain Name System] or web server misconfiguration may exist.',
                        [ $url, $_->get('status'), $_->get('reason') ],
                        { redirects_count => $redirects_count, redirects => $redirects },
                    );

                }
            }
            elsif ( $final_url ne $url ) {
                die Cpanel::Exception->create(
                    'The system queried for a temporary file at “[output,url,_1]”, which was redirected from “[output,url,_2]”. The web server responded with the following error: [_3] ([_4]). A [output,abbr,DNS,Domain Name System] or web server misconfiguration may exist. The domain “[_5]” resolved to an [asis,IP] address “[_6]” that does not exist on this server.',
                    [ $final_url, $url, $_->get('status'), $_->get('reason'), $domain, $test_ip ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );

            }
            else {
                die Cpanel::Exception->create(
                    'The system queried for a temporary file at “[output,url,_1]”, but the web server responded with the following error: [_2] ([_3]). A [output,abbr,DNS,Domain Name System] or web server misconfiguration may exist. The domain “[_4]” resolved to an [asis,IP] address “[_5]” that does not exist on this server.',
                    [ $url, $_->get('status'), $_->get('reason'), $domain, $test_ip ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );

            }
        }

        #If the exception was something other than HTTP::Server,
        #we can safely assume that there is no other URL in play.
        if ($ip_is_local) {
            if ( $final_url ne $url ) {
                die Cpanel::Exception->create(
                    'The system failed to fetch the [output,abbr,DCV,Domain Control Validation] file at “[output,url,_1]”, which was redirected from “[output,url,_2]”, because of an error: [_3].',
                    [ $final_url, $url, Cpanel::Exception::get_string_no_id($_) ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );
            }
            else {
                die Cpanel::Exception->create(
                    'The system failed to fetch the [output,abbr,DCV,Domain Control Validation] file at “[output,url,_1]” because of an error: [_2].',
                    [ $url, Cpanel::Exception::get_string_no_id($_) ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );
            }
        }
        else {
            if ( $final_url ne $url ) {
                die Cpanel::Exception->create(
                    'The system failed to fetch the [output,abbr,DCV,Domain Control Validation] file at “[output,url,_1]”, which was redirected from “[output,url,_2]”, because of an error: [_3]. The domain “[_4]” resolved to an [asis,IP] address “[_5]” that does not exist on this server.',
                    [ $final_url, $url, Cpanel::Exception::get_string_no_id($_), $domain, $test_ip ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );
            }
            else {
                die Cpanel::Exception->create(
                    'The system failed to fetch the [output,abbr,DCV,Domain Control Validation] file at “[output,url,_1]” because of an error: [_2]. The domain “[_3]” resolved to an [asis,IP] address “[_4]” that does not exist on this server.',
                    [ $url, Cpanel::Exception::get_string_no_id($_), $domain, $test_ip ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );
            }
        }
    };

    my $redirects       = $request_obj->redirects();
    my $redirects_count = scalar @$redirects;

    if ( $sanity_fetched ne $content ) {

        my $final_url = $request_obj->url();

        my $ip_is_local = _ip_is_on_local_server($test_ip) ? 1 : 0;

        # Strip new lines since makes the error easier to understand
        my $sanity_copy = $sanity_fetched =~ tr<\r\n>< >r;

        my $content_preview = substr( $sanity_copy, 0, 128 );
        $content_preview .= ' …' if length $sanity_copy > 128;

        # Its possible they have some type of proxy setup so lets try it
        # first and only complain that the ip is not local if it fails
        my $err;
        if ($ip_is_local) {
            if ( $final_url ne $url ) {
                $err = Cpanel::Exception->create(
                    'The content “[_1]” of the [output,abbr,DCV,Domain Control Validation] file, as accessed at “[output,url,_2]” and redirected from “[output,url,_3]”, did not match the expected value.',
                    [ $content_preview, $final_url, $url ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );
            }
            else {
                $err = Cpanel::Exception->create(
                    'The content “[_1]” of the [output,abbr,DCV,Domain Control Validation] file, as accessed at “[output,url,_2]”, did not match the expected value.',
                    [ $content_preview, $url ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );
            }
        }
        else {
            if ( $final_url ne $url ) {
                $err = Cpanel::Exception->create(
                    'The content “[_1]” of the [output,abbr,DCV,Domain Control Validation] file, as accessed at “[output,url,_2]” and redirected from “[output,url,_3]”, did not match the expected value. The domain “[_4]” resolved to an [asis,IP] address “[_5]” that does not exist on this server.',
                    [ $content_preview, $final_url, $url, $domain, $test_ip ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );
            }
            else {
                $err = Cpanel::Exception->create(
                    'The content “[_1]” of the [output,abbr,DCV,Domain Control Validation] file, as accessed at “[output,url,_2]”, did not match the expected value. The domain “[_3]” resolved to an [asis,IP] address “[_4]” that does not exist on this server.',
                    [ $content_preview, $url, $domain, $test_ip ],
                    { redirects_count => $redirects_count, redirects => $redirects },
                );
            }
        }

        # case CPANEL-13158: limit logging of failed DCV to 1024 bytes
        # to avoid filling up the log.
        my $spew_limit                 = 1024;
        my $fetched_length             = length $sanity_fetched;
        my $sanity_fetched_big_preview = substr( $sanity_fetched, 0, $spew_limit ) =~ tr<\r\n>< >r;
        $sanity_fetched_big_preview .= ' …' if $fetched_length > $spew_limit;

        local $Cpanel::Logger::ENABLE_BACKTRACE = 0;
        Cpanel::Logger->new()->warn( "XID " . $err->id() . ": expected “$content” from “$final_url” but received “$sanity_fetched_big_preview” ($fetched_length bytes)" );

        die $err;
    }

    return {
        redirects       => $redirects,
        redirects_count => $redirects_count,
    };
}

sub _build_and_validate_dcv_config_from_args {
    my (%OPTS) = @_;

    my $dcv_config = {};

    $dcv_config->{'dcv_file_relative_path'}          = $OPTS{'dcv_file_relative_path'}          || Cpanel::SSL::DCV::Ballot169::Constants::URI_DCV_RELATIVE_PATH();
    $dcv_config->{'dcv_file_extension'}              = $OPTS{'dcv_file_extension'}              || $DEFAULT_TEMP_FILE_EXTENSION;
    $dcv_config->{'dcv_file_random_character_count'} = $OPTS{'dcv_file_random_character_count'} || $DEFAULT_TEMP_FILE_RANDOM_CHARACTER_COUNT;
    $dcv_config->{'dcv_file_allowed_characters'}     = $OPTS{'dcv_file_allowed_characters'}     || $DEFAULT_TEMP_FILE_RANDOM_CHARACTERS;
    $dcv_config->{'dcv_user_agent_string'}           = $OPTS{'dcv_user_agent_string'}           || undef;
    $dcv_config->{'dcv_max_redirects'}               = $OPTS{'dcv_max_redirects'} // undef;    # 0 is a valid value

    my $bad_chars = {
        "\0" => 1,
        '/'  => 1,
    };

    if ( ref $dcv_config->{'dcv_file_allowed_characters'} ne 'ARRAY' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be an array reference.', ['dcv_file_random_characters'] );
    }
    elsif ( grep { $bad_chars->{$_} } @{ $dcv_config->{'dcv_file_allowed_characters'} } ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must not contain the [numerate,_2,character,characters]: [join,~, ,_3]', [ 'dcv_file_random_characters', scalar keys %$bad_chars, [ '\0', '/' ] ] );
    }

    if ( length $dcv_config->{'dcv_file_relative_path'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Validate::FilesystemPath');
        Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes( $dcv_config->{'dcv_file_relative_path'} );
        Cpanel::Validate::FilesystemPath::validate_or_die( $dcv_config->{'dcv_file_relative_path'} );
    }

    if ( length $dcv_config->{'dcv_file_extension'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Validate::FilesystemNodeName');
        Cpanel::Validate::FilesystemNodeName::validate_or_die( $dcv_config->{'dcv_file_extension'} );
    }

    return $dcv_config;
}

sub _generate_dcv_file_and_get_fh {
    my ( $dcv_config, $docroot ) = @_;

    my ( $filepath, $fh, $temp_obj );

    my ( $file_extension, $relative_path, $allowed_characters, $random_character_count ) = @{$dcv_config}{qw(dcv_file_extension dcv_file_relative_path dcv_file_allowed_characters dcv_file_random_character_count )};

    my $OPEN_FLAGS ||= Cpanel::Fcntl::or_flags(qw( O_WRONLY O_EXCL O_CREAT ));
    my ( $temp_file_path, $attempts, $last_error );

    my $base_path = _get_base_path( $docroot, $relative_path );
    my $end_path  = length $file_extension ? ( substr( $file_extension, 0, 1 ) eq '.' ? $file_extension : ".$file_extension" ) : '';

    for ( $attempts = 0; $attempts < $MAX_TEMP_FILE_CREATION_ATTEMPTS; $attempts++ ) {
        my $filename = Cpanel::Rand::Get::getranddata( $random_character_count, $allowed_characters );
        $temp_file_path = "$base_path/$filename$end_path";

        # No need to check -e as we open with O_EXCL
        if ( sysopen( $fh, $temp_file_path, $OPEN_FLAGS, 0600 ) ) {
            $filepath = $temp_file_path;
            last;
        }
        $last_error = $!;
    }

    if ( $attempts >= $MAX_TEMP_FILE_CREATION_ATTEMPTS || !length $filepath ) {
        die Cpanel::Exception::create( 'TempFileCreateError', [ path => $temp_file_path, error => $last_error ] );
    }

    $temp_obj = Cpanel::Finally->new(
        sub {
            unlink $filepath;    # no need to check -e as always want to unlink
        }
    );

    return ( $filepath, $fh, $temp_obj );
}

sub _get_base_path {
    my ( $docroot, $relative_path ) = @_;

    return $docroot if !length $relative_path;

    Cpanel::LoadModule::load_perl_module('Cpanel::Mkdir');
    Cpanel::LoadModule::load_perl_module('Cpanel::Path::Normalize');

    my $path = Cpanel::Path::Normalize::normalize( $docroot . '/' . $relative_path );

    # Important: do not specify a mode for ensure_directory_existence_and_mode
    # to ensure we do not overwrite the user's choice.  If it does not exist,
    # it will be created with 0755
    Cpanel::Mkdir::ensure_directory_existence_and_mode($path);

    return $path;
}

sub _get_ipv4_addresses_for_domain {
    my ( $domain, $dns_lookups_hr ) = @_;
    return @{ $dns_lookups_hr->{$domain}{v4} } if exists $dns_lookups_hr->{$domain};
    return _dnsroots_obj()->get_ipv4_addresses_for_domain($domain);
}

sub _get_ipv6_addresses_for_domain {
    my ( $domain, $dns_lookups_hr ) = @_;
    return @{ $dns_lookups_hr->{$domain}{v6} } if exists $dns_lookups_hr->{$domain};
    return _dnsroots_obj()->get_ipv6_addresses_for_domain($domain);

}

sub domains_are_registered {
    my (@args) = @_;

    return _domains_are_registered(@args);
}

sub _domains_are_registered {
    my (@domains) = @_;

    return _dnsroots_obj()->domains_are_registered(@domains);
}

sub _dnsroots_obj {

    return $_dns_roots ||= Cpanel::DnsRoots->new();
}

*_ip_is_on_local_server = *Cpanel::IP::LocalCheck::ip_is_on_local_server;

sub _get_local_ip ( $domain, $ip_addr ) {
    if ( Cpanel::IP::Loopback::is_loopback($ip_addr) ) {
        die Cpanel::Exception->create( '“[_1]” resolves to a loopback [asis,IP] address: [_2]', [ $domain, $ip_addr ] );
    }

    return Cpanel::NAT::get_local_ip($ip_addr);
}

my $_http_client;

#overridden in tests
sub _get_url_request {
    my ( $url, %options ) = @_;

    #No verify_SSL in case the redirect is to an SSL website.
    #We don’t care whether the SSL is valid or not.
    $_http_client ||= Cpanel::HTTP::Client->new(
        verify_SSL => 0,
        ( length $options{'max_redirects'} ? ( max_redirect => ( $options{'max_redirects'} + 1 ) ) : () ),    # always do one more than allowed so we can see the error
        connect_timeout => $MAX_HTTP_CONNECT_TIMEOUT,
        timeout         => $MAX_HTTP_READ_TIMEOUT,
    );

    #We used to pass MAX_SIZE to HTTP::Tiny, but that gives us
    #exceptions that don’t have the content preview, which makes
    #debugging a lot harder than it should be. So, this solution
    #gives us that preview while still enforcing the sanity in
    #the payload size.
    my $content_so_far = q<>;
    $options{'data_callback'} = sub {
        $content_so_far .= $_[0];
        if ( length($content_so_far) > MAX_SIZE() ) {

            my $content_preview = substr( $content_so_far, 0, 128 );

            # Strip new lines since makes the error easier to understand
            $content_preview =~ tr<\r\n>< >d;

            #We could give a more descriptive phrase here, but in testing
            #we found that upper layers added enough context for it to be
            #clear what’s going on here. This is an unfortunate tight
            #coupling to the current calling context but one that will
            #make life easier for customers and technical support.
            die Cpanel::Exception->create( 'The response exceeded the maximum length ([format_bytes,_1]). ([_2] …)', [ MAX_SIZE(), $content_preview ] )->to_string();
        }
    };

    $_http_client->die_on_http_error();

    my $response = $_http_client->get( $url, \%options );

    if ($response) {
        $response->{'content'} ||= $content_so_far;
    }

    return $response;
}

sub clear_cache {
    undef $_http_client;
    undef $_dns_roots;
    %_cached_down_hosts_errors = ();
    return 1;
}

sub _get_domain_from_url {
    my ($url) = @_;
    my ( $schema, $authority ) = URI::Split::uri_split($url);

    if ( $schema ne 'http' ) {
        die Cpanel::Exception->create_raw("HTTP only (not “$url”)!");
    }

    my ($domain) = split m<:>, $authority, 2;
    return $domain;
}

sub _err_because_no_ips {
    my ($domain) = @_;

    return Cpanel::Exception->create( '“[_1]” does not resolve to any [asis,IP] addresses on the internet.', [$domain] );
}

sub _err_because_ip_is_private {
    my ($domain) = @_;

    return Cpanel::Exception->create( '“[_1]” resolves to a private [asis,IP] address. The system will skip [asis,HTTP] [output,abbr,DCV,Domain Control Validation] for “[_1]”.', [$domain] );
}

1;
