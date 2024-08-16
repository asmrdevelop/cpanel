package Whostmgr::Transfers::ConvertAddon::MigrateData;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception          ();
use Cpanel::PwCache            ();
use Cpanel::LoadModule         ();
use Cpanel::Validate::Username ();

sub new {
    my ( $class, $opts_hr ) = @_;

    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] ) if $class eq __PACKAGE__;
    if ( !( $opts_hr && 'HASH' eq ref $opts_hr ) ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] detailing the data migration' );    ## no extract maketext (developer error message. no need to translate)
    }
    _validate_required_params($opts_hr);

    return bless {
        'from_username' => $opts_hr->{'from_username'},
        'to_username'   => $opts_hr->{'to_username'},
        '_warnings_ar'  => [],
    }, $class;
}

sub safesync_dirs {
    my ( $self, $opts_hr ) = @_;

    $self->ensure_users_exist();

    foreach my $dir (qw(source_dir target_dir)) {
        die Cpanel::Exception::create( 'InvalidParameter', 'You must specify a [_1] path.', [$dir] )    ## no extract maketext (developer error message. no need to translate)
          if !length $opts_hr->{$dir};
        $opts_hr->{$dir} =~ s/\/$//;                                                                    # strip any trailing slashes as they interfere with '-l' tests.
    }

    Cpanel::LoadModule::load_perl_module('Capture::Tiny');
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeSync::UserDir');
    my ( $source_user_uid, $source_user_gid ) = ( Cpanel::PwCache::getpwnam( $self->{'from_username'} ) )[ 2, 3 ];
    my ( $target_user_uid, $target_user_gid ) = ( Cpanel::PwCache::getpwnam( $self->{'to_username'} ) )[ 2, 3 ];

    if ( -l $opts_hr->{'source_dir'} ) {
        die Cpanel::Exception->create( 'The source directory, [_1], is a symlink, and will not be copied.', [ $opts_hr->{'source_dir'} ] );
    }

    if ( !-e $opts_hr->{'target_dir'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');

        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                Cpanel::SafeDir::MK::safemkdir( $opts_hr->{'target_dir'} );
                chown $target_user_uid, $target_user_gid, $opts_hr->{'target_dir'}
                  or die Cpanel::Exception::create( 'IO::ChownError', [ 'error' => $!, 'uid' => $target_user_uid, 'gid' => $target_user_gid, 'path' => $opts_hr->{'target_dir'} ] );
            },
            $target_user_uid,
            $target_user_gid,
        );
    }
    elsif ( !-d $opts_hr->{'target_dir'} ) {
        die Cpanel::Exception->create( 'The target path, [_1], already exists, but is not a directory.', [ $opts_hr->{'target_dir'} ] );
    }

    # The warnings we really want to capture from this process
    # are the STDERR warnings from the tar calls.
    #
    # The "internal" warnings are logged to logs/error_log
    my $return = 0;
    my $stderr = Capture::Tiny::capture_stderr(
        sub {
            $return = Cpanel::SafeSync::UserDir::sync_to_userdir(
                'source'                => $opts_hr->{'source_dir'},
                'target'                => $opts_hr->{'target_dir'},
                'setuid'                => [ $target_user_uid, $target_user_gid ],
                'wildcards_match_slash' => 0,
                'overwrite_public_html' => 0,
                'source_setuid'         => [ $source_user_uid, $source_user_gid ],
            );
        }
    );
    $self->add_warning($_) for ( split /\n/, $stderr );
    return $return;
}

sub ensure_users_exist {
    my $self = shift;

    Cpanel::Validate::Username::user_exists_or_die( $self->{'from_username'} );
    Cpanel::Validate::Username::user_exists_or_die( $self->{'to_username'} );
    return 1;
}

sub has_warnings   { return scalar @{ $_[0]->{'_warnings_ar'} }; }
sub get_warnings   { return $_[0]->{'_warnings_ar'}; }
sub reset_warnings { return $_[0]->{'_warnings_ar'} = []; }
sub add_warning    { return push @{ $_[0]->{'_warnings_ar'} }, $_[1] =~ s/[\s]+$//r; }

sub _validate_required_params {
    my $opts = shift;

    my @exceptions;
    foreach my $required_arg (qw(from_username to_username)) {
        if ( not defined $opts->{$required_arg} ) {
            push @exceptions, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_arg] );
        }
        elsif ( $required_arg eq 'from_username' && !eval { Cpanel::Validate::Username::user_exists_or_die( $opts->{$required_arg} ); 1; } ) {
            push @exceptions, $@;
        }
    }

    die Cpanel::Exception::create( 'Collection', 'Invalid or Missing required parameters', [], { exceptions => \@exceptions } ) if scalar @exceptions;
    return 1;
}

1;
