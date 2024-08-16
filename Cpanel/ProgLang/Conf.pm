package Cpanel::ProgLang::Conf;

# cpanel - Cpanel/ProgLang/Conf.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::CachedDataStore      ();
use Cpanel::ConfigFiles::Apache  ();
use Cpanel::Config::SimpleCpConf ();
use Cpanel::Exception            ();

our $CONFIG_DIR = '/etc/cpanel/ea4';

sub new {
    my ( $class, %args ) = @_;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'type' ] ) unless defined $args{type};
    $args{type} = lc $args{type};
    return bless( \%args, $class );
}

# Retrieve the path to the cPanel configuration file that tells us
sub get_file_path {
    my ( $self, %args ) = @_;
    my $path;

    # EA3 stored the conf.yaml file in the apache configuration directory, but
    # wasn't suitable for Apache to use it.  Thus, the configuration file is
    # being moved to $CONFIG_DIR, where config files should actually live.

    if ( $args{legacy} ) {
        my $apacheconf = Cpanel::ConfigFiles::Apache->new();
        $path = sprintf( '%s/%s.conf.yaml', $apacheconf->dir_conf(), $self->{type} );
    }
    else {
        $path = sprintf( '%s/%s.conf', $CONFIG_DIR, $self->{type} );
    }

    return $path;
}

# Retrieve the contents of the cPanel configuration file for a language type
sub get_conf {
    my ($self) = @_;

    # Configuration file is being migrated from legacy location, to new
    # location.  So, we'll try to load where it should be.  If it's not
    # there, we'll try the legacy spot.  This will ensure that when ever
    # we save, we just save to the new location.
    my $fname = $self->get_file_path();
    $fname = $self->get_file_path( legacy => 1 ) if !-f $fname;

    my $ref = Cpanel::CachedDataStore::fetch_ref($fname);

    # Legacy: The original conf stored the default as 'phpversion'.  This
    # has been migrated to 'default' so that any language can use this module.
    $ref->{default} = delete $ref->{phpversion} if $ref->{phpversion};
    delete $ref->{$_} for qw( dryrun suexec php4 php5 );    # precaution to make sure we don't have old ea3 data in this

    if ( !$ref->{default} ) {
        if ( $self->{type} eq 'php' ) {                     # this should be done via the proglang object, see ZC-2610
            require Cpanel::EA4::Util;
            $ref->{default} = "ea-php" . Cpanel::EA4::Util::get_default_php_version();
            $ref->{default} =~ s/\.//;
        }
        else {
            warn "No default “$self->{type}” set\n";
        }
    }

    # Create fake bless so we can type check this later
    return $ref;
}

# Update the contents of the cPanel configuration file for a language type
sub set_conf {
    my ( $self, %args ) = @_;
    my $ref = $args{conf};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'conf' ] ) unless defined $ref;

    # Legacy: The original conf stored the default as 'phpversion'.  This
    # has been migrated to 'default' so that any language can use this module.
    $ref->{default} = delete $ref->{phpversion} if $ref->{phpversion};

    # Always save to the new file location, not legacy
    my $path = $self->get_file_path();

    _backup_file($path) if -e $path;

    # Legacy: Remove old location if we successful updated the new one
    # to prevent a 2 similar config files from laying around.
    if ( Cpanel::CachedDataStore::store_ref( $path, $ref ) ) {
        my $old = $self->get_file_path( legacy => 1 );
        unlink $old;
    }

    return 1;
}

sub _backup_file {
    my ( $file, $verbose ) = @_;

    if ( !-e $file ) {    # detect missing file (or dir FTM) or broken symlink
        warn "“$file” (or its target if its a symlink) does not exist: nothing to backup\n";
        return 1;
    }

    if ( !-f _ ) {

        # if this was made reusable this should probably be an exception.
        #     Its not right now because:
        #        a. we don't have an exception for this and making one is major scope creep
        #        b. if they are in this state then they have manually broken their server
        #            (i.e. php.conf can not naturally be in this state and its not very likley that root would put it in that state
        #               since that would break their system so its extremely unlikely this will hit w/ php.conf)
        warn "“$file” is not a normal file (or a symlink to a normal file): can not back it up\n";
        return;
    }

    my $bu_dir = "$file.bak";
    mkdir $bu_dir if !-d $bu_dir;
    my $timestamp = _time();                    # ¿TODO/YAGNI make this more ISO 8601 (i.e. 2018-04-31T10:19:42Z) for humans?
    my $bu_path   = "$bu_dir/$timestamp.$$";    # if the same process wants to race itself then not a problem :) safecopy would likely catch it anyway so its even less of an issue
    require Cpanel::FileUtils::Copy;
    Cpanel::FileUtils::Copy::safecopy( $file, $bu_path ) or return;    # safecopy() already spews warnings and errors

    # erase older backups, only keep the last N
    my @backups = sort glob("$bu_dir/*");                              # bsd_glob() does not work, returns the argument as-is :/
    my @remove  = splice( @backups, 0, -20 );
    if (@remove) {
        if ( unlink(@remove) != @remove ) {
            warn "Could not cleanup older $file backups: $!\n";
        }
    }

    return 1;
}

sub _time {
    return time();
}

# Retrieve information for a specific package in the cPanel configuration
sub get_package_info {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'package' ] ) unless defined $args{package};

    my $ref = $self->get_conf();
    return $ref->{ $args{package} };
}

# Set information for a specific package in the cPanel configuration
sub set_package_info {
    my ( $self, %args ) = @_;

    my $package = $args{package};
    my $info    = $args{info};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'package' ] ) unless defined $package;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'info' ] )    unless defined $info;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be a valid parameter type: [_2]', [ 'info', 'SCALAR' ] ) unless ref($info) eq '';

    # TODO:  Error handling!
    # MAYBE TODO:  Locking?

    my $conf = $self->get_conf();
    $conf->{$package} = $info;
    return $self->set_conf( conf => $conf );
}

# Retrieve the default package used by the system.
# NOTE: This is just a wrapper around get_package_info() but passes
# the 'default' string.
sub get_system_default_package {
    my ($self) = @_;

    # Legacy: Load from the new location before looking at legacy to ease
    # the transition.
    my $cfg = Cpanel::Config::SimpleCpConf::get_cpanel_config();
    my $key = sprintf( '%s_system_default_version', $self->{type} );

    return ( $self->get_package_info( package => 'default' ) || $cfg->{$key} );
}

# Set the default package used by the system.
# NOTE: This is just a wrapper around set_package_info() but passes
# the 'default' string.
sub set_system_default_package {
    my ( $self, %args ) = @_;

    # TODO: Remove these checks once ZC-1018 is implemented
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'info' ] ) unless defined $args{info};
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be a valid parameter type: [_2]', [ 'info', 'SCALAR' ] ) unless ref( $args{info} ) eq '';

    # TODO: Stop writing to cpanel.config after implementing ZC-1018
    my $key = sprintf( '%s_system_default_version', $self->{type} );

    my $cfg = Cpanel::Config::SimpleCpConf::get_cpanel_config();
    if ( !$cfg->{$key} || $cfg->{$key} ne $args{info} ) {
        Cpanel::Config::SimpleCpConf::set_cpanel_config( { $key => $args{info} } );
    }

    # TODO: Delete the cpanel.config entry after implementing ZC-1018

    # Write to new location as well until ZC-1018 is implemented
    return $self->set_package_info( package => 'default', info => $args{info} );
}

1;

__END__

=head1 NAME

Cpanel::ProgLang::Conf

Note: All Cpanel::ProgLang namespaces and some attribute inconsistencies will change in ZC-1202. If you need to use Cpanel::ProgLang please note the specifics in ZC-1202 so the needful can be had.
