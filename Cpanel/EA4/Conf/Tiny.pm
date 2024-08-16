package Cpanel::EA4::Conf::Tiny;

# cpanel - Cpanel/EA4/Conf/Tiny.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $CONFPATH = "/etc/cpanel/ea4/ea4.conf";
use Cpanel::Transaction::File::JSONReader ();

# not a reference or package global because we do not want callers to modify this
use constant DEFAULTS => (

    # This static `directoryindex` is replaced by ea-cpanel-tool’s ea4-metainfo.json’s `default_directoryindex`
    directoryindex       => 'index.php index.php8 index.php7 index.php5 index.perl index.pl index.plx index.ppl index.cgi index.jsp index.jp index.phtml index.shtml index.xhtml index.html index.htm index.js',
    extendedstatus       => "On",
    fileetag             => "None",
    keepalive            => "On",
    keepalivetimeout     => 5,
    logformat_combined   => '%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"',
    logformat_common     => '%h %l %u %t \"%r\" %>s %b',
    loglevel             => "warn",
    maxclients           => 150,
    maxkeepaliverequests => 100,
    maxrequestsperchild  => 10_000,
    maxspareservers      => 10,
    minspareservers      => 5,
    rlimit_cpu_hard      => "",
    rlimit_cpu_soft      => 240,
    rlimit_mem_hard      => "",
    rlimit_mem_soft      => "",
    root_options         => "ExecCGI FollowSymLinks IncludesNOEXEC Indexes",

    # serveradmin && servername are readonly/dynamic so we set it undef here
    serveradmin => undef,
    servername  => undef,

    serverlimit     => 256,
    serversignature => "Off",
    servertokens    => "ProductOnly",

    # sslciphersuite, sslprotocol, sslprotocol_list_str are not readonly/dynamic, just want to lazy load the defaults module
    sslciphersuite       => undef,
    sslprotocol          => undef,
    sslprotocol_list_str => undef,    # this is derived from sslprotocol

    sslusestapling => "On",

    startservers    => 5,
    symlink_protect => "Off",
    threadsperchild => 25,
    timeout         => 300,
    traceenable     => "Off",
    local_attrs     => {},
);

my $ea4_conf_hr;
sub reset_memory_cache { $ea4_conf_hr = undef; return; }

sub DEFAULTS_filled_in {
    require Perl::Phase;
    Perl::Phase::assert_is_run_time();

    require Cpanel::HttpUtils::Conf;
    require Cpanel::SSL::Defaults;
    require Cpanel::SSL::Protocols;

    my $sslprotocol = Cpanel::SSL::Defaults::default_protocol_list( { type => 'positive', delimiter => ' ' } );
    $sslprotocol = Cpanel::SSL::Protocols::upgrade_version_string_for_tls_1_2_apache($sslprotocol);
    my %updates = (
        sslprotocol          => $sslprotocol,
        sslprotocol_list_str => $sslprotocol,
        sslciphersuite       => scalar( Cpanel::SSL::Defaults::default_cipher_list() ),
        servername           => scalar( Cpanel::HttpUtils::Conf::get_main_server_name() ),
        serveradmin          => scalar( Cpanel::HttpUtils::Conf::get_main_server_admin() ),
    );

    if ( Cpanel::SSL::Defaults::ea4_has_tls13() ) {
        $updates{'sslciphersuite'} .= ":TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256";
    }

    my $trx = eval { Cpanel::Transaction::File::JSONReader->new( path => "/etc/cpanel/ea4/ea4-metainfo.json" ) };
    if ( !$@ && ref( my $data = $trx->get_data ) eq 'HASH' ) {
        $updates{directoryindex} = $data->{default_directoryindex} if exists $data->{default_directoryindex};
    }

    return (
        DEFAULTS,
        %updates,
    );
}

sub get_ea4_conf_hr {
    return $ea4_conf_hr if $ea4_conf_hr;

    my $trx = eval { Cpanel::Transaction::File::JSONReader->new( path => $CONFPATH ) };
    return $ea4_conf_hr = { DEFAULTS_filled_in() } if $@;

    my $data = $trx->get_data;
    $ea4_conf_hr = {
        DEFAULTS_filled_in(),
        %{ ref($data) eq "SCALAR" ? {} : $data },
    };

    return $ea4_conf_hr;
}

sub get_ea4_conf_distiller_hr {
    my $ea4cnf_hr = get_ea4_conf_hr();

    my $output_hr = _get_distiller_conf_defaults();

    _standard_distiller_item( serveradmin    => $output_hr );
    _standard_distiller_item( directoryindex => $output_hr );
    _standard_distiller_item( extendedstatus => $output_hr );
    _standard_distiller_item( loglevel       => $output_hr );

    if ( $ea4cnf_hr->{rlimit_mem_soft} ne '' && $ea4cnf_hr->{rlimit_mem_soft} > 0 ) {
        $output_hr->{main}{rlimitcpu} = {
            directive => 'rlimitcpu',
            item      => {
                maxrlimitcpu  => scalar( $ea4cnf_hr->{rlimit_cpu_hard} ),
                softrlimitcpu => scalar( $ea4cnf_hr->{rlimit_cpu_soft} ),
            }
        };
        $output_hr->{main}{rlimitmem} = {
            directive => 'rlimitmem',
            item      => {
                maxrlimitmem  => ( scalar( $ea4cnf_hr->{rlimit_mem_hard} ) ),
                softrlimitmem => ( scalar( $ea4cnf_hr->{rlimit_mem_soft} ) ),
            }
        };
    }

    _standard_distiller_item( logformat_combined => $output_hr );
    _standard_distiller_item( logformat_common   => $output_hr );
    $output_hr->{main}{logformat} = {
        directive => 'logformat',
        items     => [
            { logformat => q{"%v:%p %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combinedvhost} },
            { logformat => q{"} . $ea4cnf_hr->{logformat_combined} . qq{" combined} },
            { logformat => q{"} . $ea4cnf_hr->{logformat_common} . qq{" common} },
            { logformat => q{"%{Referer}i -> %U" referer} },
            { logformat => q{"%{User-agent}i" agent} },
        ],
    };

    _standard_distiller_item( sslciphersuite       => $output_hr );
    _standard_distiller_item( sslusestapling       => $output_hr );
    _standard_distiller_item( sslprotocol          => $output_hr );
    _standard_distiller_item( traceenable          => $output_hr );
    _standard_distiller_item( serversignature      => $output_hr );
    _standard_distiller_item( servertokens         => $output_hr );
    _standard_distiller_item( fileetag             => $output_hr );
    _standard_distiller_item( startservers         => $output_hr );
    _standard_distiller_item( minspareservers      => $output_hr );
    _standard_distiller_item( maxspareservers      => $output_hr );
    _standard_distiller_item( serverlimit          => $output_hr );
    _standard_distiller_item( threadsperchild      => $output_hr );
    _standard_distiller_item( maxclients           => $output_hr );
    _standard_distiller_item( maxrequestsperchild  => $output_hr );
    _standard_distiller_item( keepalive            => $output_hr );
    _standard_distiller_item( keepalivetimeout     => $output_hr );
    _standard_distiller_item( maxkeepaliverequests => $output_hr );

    _standard_distiller_item( timeout         => $output_hr );
    _standard_distiller_item( symlink_protect => $output_hr );

    $output_hr->{main}{directory} = {
        options => {
            directive => 'options',
            item      => {
                options => scalar( $ea4cnf_hr->{root_options} ),
            },
        },
    };

    _standard_distiller_item( servername => $output_hr );

    return $output_hr;
}

sub _get_distiller_conf_defaults {

    require Cpanel::ConfigFiles::Apache;
    my $apache_paths = Cpanel::ConfigFiles::Apache::apache_paths_facade();

    return {
        # cruft: service                       => 'apache',
        _initialized                  => 0,
        _target_conf_file             => scalar( $apache_paths->file_conf() ),
        _follow                       => '',
        serve_apache_manual           => 1,
        serve_server_status           => 0,
        serve_server_info             => 0,
        allow_server_info_status_from => '',
        serverroot                    => scalar( $apache_paths->dir_base() ),
        custom                        => {},

        # 'dcv_rewrite_patterns'           Now provided by Cpanel::Template::Plugins::Apache
        includes => {
            cpanel    => '',
            user      => '',
            vhost     => '',
            ssl_vhost => '',
        },
        vhosts     => undef,
        ssl_vhosts => undef,
    };
}

sub _standard_distiller_item {
    my ( $name, $hr, $attr ) = @_;
    $attr ||= $name;    # in case the old name does not match the new attribute name

    my $ea4cnf = get_ea4_conf_hr();

    $hr->{main}{$name} = {
        item      => { $name => scalar( $ea4cnf->{$attr} ), },
        directive => $name,
    };

    return $hr;
}

1;

__END__

=encoding utf8

=head1 NAME

Cpanel::EA4::Conf::Tiny - load EA4 conf file

=head1 SYNOPIS

   use Cpanel::EA4::Conf::Tiny ();

   my $ea4cnf_hr = Cpanel::EA4::Conf::Tiny::get_ea4_conf_hr();

Then in the template:

   [% ea4conf.directoryindex %]

=head1 DESCRIPTION

Cpanel::EA4::Conf::Tiny  consolidates general WebServer configuration options into
a single JSON file.

=head1 FUNCTIONS

=head2 get_ea4_conf_hr()

Takes no arguments. Returns the EA4 conf file as a hashref.

=head2 reset_memory_cache()

Takes no arguments. Returns nothing,

It resets the internal cache that L<get_ea4_conf_hr()> populates and reuses on subsequent calls.

That is really only useful in testing and in L<Cpanel::EA4::Conf>’s C<save()>.

=head2 DEFAULTS_filled_in()

Takes no arguments. Returns C<DEFAULTS> with w/ values that need looked up filled in.

=head1 CONSTANTS

=head2 DEFAULTS

    print Dumper({ Cpanel::EA4::Conf::Tiny::DEFAULTS });

Values that need looked up are C<undef>. If you want those values filled in use C<DEFAULTS_filled_in()> instead.

=head1 ADDING A NEW CONFIG ATTR METHOD

See L<Cpanel::EA4::Conf/"ADDING A NEW CONFIG ATTR METHOD"> for details.
