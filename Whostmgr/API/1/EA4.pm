package Whostmgr::API::1::EA4;

#                                       Copyright 2024 WebPros International, LLC
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use strict;
use warnings;
use Capture::Tiny ();

use Cpanel::Imports;
use Cpanel::SafeDir::Read                ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::Exception                    ();
use Cpanel::JSON                         ();
use Cpanel::LoadModule                   ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::Form::Param                  ();
use Cpanel::Validate::FilesystemNodeName ();
use Whostmgr::API::1::Utils              ();
use Cpanel::Rlimit                       ();
use Cpanel::API::EA4                     ();
use Cpanel::Result                       ();

use constant NEEDS_ROLE => 'WebServer';

# mostly for testing
sub _get_profile_dir { return '/etc/cpanel/ea4/profiles'; }

our $tomcat85_modulino = "/usr/local/cpanel/scripts/ea-tomcat85";

sub ea4_get_additional_pkg_prefixes {
    my ( $args, $metadata ) = @_;

    my @additional_pkg_prefixes = sort( Cpanel::SafeDir::Read::read_dir("/etc/cpanel/ea4/additional-pkg-prefixes/") );

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { additional_pkg_prefixes => \@additional_pkg_prefixes };
}

sub ea4_metainfo {
    my ( $args, $metadata ) = @_;
    my $result = eval { Cpanel::JSON::LoadFile("/etc/cpanel/ea4/ea4-metainfo.json") } || {};

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return $result;
}

sub ea4_recommendations {
    my ( $args, $metadata ) = @_;

    my $result = Cpanel::Result->new();
    Cpanel::API::EA4::get_recommendations( $args, $result );

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return $result->{data};
}

sub ea4_list_profiles {
    my ( $args, $metadata ) = @_;

    my %profile_data;

    my @active_pkgs;

    Cpanel::LoadModule::load_perl_module('Cpanel::PackMan');

    # setup the "currently installed" profile
    my $ea4 = Cpanel::PackMan->instance( type => 'ea4' );

    for my $prefix ( "ea", Cpanel::SafeDir::Read::read_dir("/etc/cpanel/ea4/additional-pkg-prefixes/") ) {
        for my $pkg ( $ea4->list( state => 'installed', 'prefix' => "$prefix-" ) ) {
            push @active_pkgs, $pkg;
        }
    }

    push @{ $profile_data{'cpanel'} },
      {
        'version'         => '1.0',
        'desc'            => locale->maketext('The currently installed packages on the server.'),
        'pkgs'            => \@active_pkgs,
        'name'            => locale->maketext('Current Profile'),
        'active'          => 1,
        'validation_data' => { not_on_server => [] },
      };

    my %server_pkgs;
    for my $prefix ( "ea", Cpanel::SafeDir::Read::read_dir("/etc/cpanel/ea4/additional-pkg-prefixes/") ) {
        @server_pkgs{ $ea4->list( prefix => "$prefix-" ) } = ();
    }

    my $dir = _get_profile_dir() . "/cpanel";
    for my $cpanel_profile ( sort( Cpanel::SafeDir::Read::read_dir($dir) ) ) {
        my $profile = _get_profile_hr( $dir, $cpanel_profile, \%server_pkgs );
        next if !$profile;
        push @{ $profile_data{'cpanel'} }, $profile;
    }

    $dir = _get_profile_dir() . "/custom";
    for my $custom_profile ( sort( Cpanel::SafeDir::Read::read_dir($dir) ) ) {
        my $profile = _get_profile_hr( $dir, $custom_profile, \%server_pkgs );
        next if !$profile;
        push @{ $profile_data{'custom'} }, $profile;
    }

    $dir = _get_profile_dir() . "/vendor";
    for my $vendor ( sort( Cpanel::SafeDir::Read::read_dir($dir) ) ) {
        next if !-d "$dir/$vendor";

        if ( $vendor =~ m/^(?:cpanel|custom)$/i ) {
            logger->info("Ignoring vendor “$vendor” because it is a reserved word.");
            next;
        }

        for my $vendor_profile ( sort( Cpanel::SafeDir::Read::read_dir("$dir/$vendor") ) ) {
            my $profile = _get_profile_hr( "$dir/$vendor", $vendor_profile, \%server_pkgs );
            next if !$profile;
            push @{ $profile_data{$vendor} }, $profile;
        }
    }

    if ( !keys %profile_data ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext('No profiles found.');
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return \%profile_data;
}

sub ea4_get_currently_installed_packages {
    my ( $args, $metadata ) = @_;

    # Get "currently installed" packages
    Cpanel::LoadModule::load_perl_module('Cpanel::PackMan');
    my $ea4 = Cpanel::PackMan->instance( type => 'ea4' );

    my @curr_installed_pkgs;
    for my $prefix ( "ea", Cpanel::SafeDir::Read::read_dir("/etc/cpanel/ea4/additional-pkg-prefixes/") ) {
        for my $pkg ( $ea4->list( state => 'installed', prefix => "$prefix-" ) ) {
            push @curr_installed_pkgs, $pkg;
        }
    }

    if ( scalar @curr_installed_pkgs <= 0 ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext('There are no packages currently installed.');
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { packages => \@curr_installed_pkgs };
}

sub _get_profile_hr {
    my ( $dir, $json_file, $on_server_hr ) = @_;
    return if !defined $json_file;
    return if $json_file !~ m/\.json$/;
    return if !Cpanel::Validate::FilesystemNodeName::is_valid($json_file);    # just in case

    my $profile = eval { Cpanel::JSON::LoadFile("$dir/$json_file") };
    if ($@) {
        logger->info("Could not load JSON in “$dir/$json_file”: $@");
        return;
    }
    if ( my $translated = locale->get_asset_file("$dir/.locale/%s/$json_file") ) {
        my $lexicon = eval { Cpanel::JSON::LoadFile($translated) };
        if ($@) {
            logger->warn($@);
        }
        else {
            for my $key (qw(name desc)) {
                next if !exists $lexicon->{$key} || !defined $lexicon->{$key} || !length Cpanel::StringFunc::Trim::ws_trim( $lexicon->{$key} );
                $profile->{$key} = $lexicon->{$key};
            }
        }
    }

    # 1. detect any packages in the profile that do not exist on the server
    my %not_on_server = ( map { !exists $on_server_hr->{$_} ? ( $_ => undef ) : () } @{ $profile->{pkgs} } );

    # 2. remove %not_on_server from $profile->{pkgs}
    $profile->{pkgs} = [ grep { !exists $not_on_server{$_} } @{ $profile->{pkgs} } ];

    # 3. add %not_on_server to $profile->{validation_data}{not_on_server}
    $profile->{validation_data}{not_on_server} = [ keys %not_on_server ];

    $profile->{path} = $json_file;

    return $profile;
}

sub ea4_tomcat85_list {
    my ( $args, $metadata ) = @_;
    _load_tomcat85( undef, $metadata );

    my ($output) = Capture::Tiny::capture_merged { scripts::ea_tomcat85::run("list") };
    my @users = grep { chomp if defined; defined && length } split( /\n/, $output );

    return { tomcat85_users => \@users };
}

sub ea4_tomcat85_add {
    my ( $args, $metadata ) = @_;

    local $ENV{"scripts::ea_tomcat85::bail_die"} = 1;
    my $limits_hr = Cpanel::Rlimit::get_current_rlimits();
    Cpanel::Rlimit::set_rlimit_to_infinity();

    my %results;
    for my $user ( _load_tomcat85( $args, $metadata ) ) {
        Capture::Tiny::capture_merged {
            eval { scripts::ea_tomcat85::run( "add", $user ) };
        };
        $results{$user} = $@;
    }

    Cpanel::Rlimit::restore_rlimits($limits_hr);
    return \%results;
}

sub ea4_tomcat85_rem {
    my ( $args, $metadata ) = @_;

    local $ENV{"scripts::ea_tomcat85::bail_die"} = 1;
    my $limits_hr = Cpanel::Rlimit::get_current_rlimits();
    Cpanel::Rlimit::set_rlimit_to_infinity();

    my %results;
    for my $user ( _load_tomcat85( $args, $metadata ) ) {
        Capture::Tiny::capture_merged {
            eval { scripts::ea_tomcat85::run( "rem", $user, "--verify=$user" ) };
        };
        $results{$user} = $@;
    }

    Cpanel::Rlimit::restore_rlimits($limits_hr);
    return \%results;
}

sub _load_tomcat85 {
    my ( $args, $metadata ) = @_;

    die "ea-tomcat85 is not installed\n" if !-e $tomcat85_modulino;
    require $tomcat85_modulino;    # Despite this not being a bareword using `no critic qw(Modules::RequireBarewordIncludes)` results in `Useless '## no critic' annotation`

    my @users;
    if ($args) {
        my $prm = Cpanel::Form::Param->new( { parseform_hr => $args } );

        @users = $prm->param('user');
        if ( !@users ) {
            die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['user'] );
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return 1 if !@users;
    return @users;
}

sub ea4_save_profile {
    my ( $args, $metadata ) = @_;
    my $prm = Cpanel::Form::Param->new( { parseform_hr => $args } );

    $metadata->{'result'} = 0;
    $metadata->{'reason'} = 'Unknown';

    # required
    my $filename = $prm->param('filename');
    my $name     = $prm->param('name');
    my @pkgs     = grep { defined && length } $prm->param('pkg');

    # optional
    my $desc      = $prm->param('desc')    || '';
    my $version   = $prm->param('version') || "0.1";
    my @tags      = grep { defined && length } $prm->param('tag');
    my $overwrite = $prm->param('overwrite') || 0;

    my $dir = _get_profile_dir() . "/custom";

    # check required values
    my @bad_params;

    # same as _get_profile_hr()
    my $filename_err;
    eval { Cpanel::Validate::FilesystemNodeName::validate_or_die($filename) };
    $filename_err = $@ if $@;
    if ( $filename_err || !defined $filename || $filename !~ m/\.json$/ ) {
        push( @bad_params, 'filename' );
    }

    if ( !defined $name || length($name) < 1 ) {    # we already checked for \s and we don't check for all the unicode possibilites so …
        push( @bad_params, 'name' );
    }

    if ( !@pkgs ) {
        push( @bad_params, 'pkg' );
    }

    if (@bad_params) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The following parameters were invalid: [list_and,_1]', \@bad_params );
        $metadata->{'reason'} .= "\nfilename: " . $filename_err->to_string if $filename_err;
        return;
    }

    if ( !-e "$dir/$filename" || $overwrite ) {
        if ( Cpanel::SafeDir::MK::safemkdir($dir) ) {
            if (
                !Cpanel::JSON::DumpFile(
                    "$dir/$filename",
                    {
                        name    => $name,
                        desc    => $desc,
                        version => $version,
                        tags    => \@tags,
                        pkgs    => \@pkgs,
                    }
                )
            ) {
                $metadata->{'result'} = 0;
                $metadata->{'reason'} = locale->maketext( "Could not write “[_1]”: [_2]", "$dir/$filename", $! );
                return;

            }
        }
        else {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = locale->maketext( "Can not create parent directory for “[_1]”: [_2]", $filename, $! );
            return;
        }

        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        return { path => "$dir/$filename" };
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The profile “[_1]” already exists and the “[_2]” param was not true.', $filename, 'overwrite' );
        return { already_exists => 1 };
    }

    return;
}

sub _pid_is_alive {
    my ($pid) = @_;

    if ( kill( 0, $pid ) ) {
        return 1;
    }

    return 0;
}
1;
