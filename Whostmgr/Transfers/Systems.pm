package Whostmgr::Transfers::Systems;

# cpanel - Whostmgr/Transfers/Systems.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A base class for account restore submodules.
#----------------------------------------------------------------------

use cPstrict;

use Try::Tiny;
use Cpanel::Config::CpUserGuard             ();
use Cpanel::SafeRun::Errors                 ();
use Cpanel::AcctUtils::Account              ();
use Cpanel::Locale                          ();
use Cpanel::Exception                       ();
use Cpanel::Reseller                        ();
use Cpanel::Reseller::Cache                 ();
use Whostmgr::Transfers::AccountRestoration ();

our $UNSUPPORTED_ACTION = 2;

use constant {
    minimum_transfer_source_version          => undef,
    minimum_transfer_source_version_for_user => undef,
};

# These are the defaults if transfer system module does not specify
sub get_relative_time { return $Whostmgr::Transfers::AccountRestoration::DEFAULT_RELATIVE_TIME }
sub get_prereq        { return $Whostmgr::Transfers::AccountRestoration::DEFAULT_PREREQ; }
sub get_phase         { return $Whostmgr::Transfers::AccountRestoration::DEFAULT_PHASE; }

sub new {
    my ( $class, %OPTS ) = @_;

    die "The required parameter 'utils' needs to be of type 'Whostmgr::Transfers::Utils'"
      if !UNIVERSAL::isa( $OPTS{'utils'}, 'Whostmgr::Transfers::Utils' );

    die "The required parameter 'archive_manager' needs to be of type 'Whostmgr::Transfers::ArchiveManager'"
      if !UNIVERSAL::isa( $OPTS{'archive_manager'}, 'Whostmgr::Transfers::ArchiveManager' );

    return bless {
        ( map { ( "_$_" => $OPTS{$_} ) } qw( utils  archive_manager disabled ) ),
    }, $class;
}

sub disabled {
    my ($self) = @_;

    return $self->{'_disabled'} || die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set during creation of “[_2]”.', [ 'disabled', ( ref $self ) ] );
}

#TODO support a hook for each module and map legacy hooks
sub olduser {
    my ($self) = @_;
    return $self->{'_utils'}->original_username();
}

sub local_username_is_different_from_original_username {
    my ($self) = @_;
    return ( $self->{'_utils'}->original_username() ne $self->{'_utils'}->local_username() ) ? 1 : 0;
}

sub newuser {
    my ($self) = @_;

    return $self->{'_utils'}->local_username();
}

sub homedir {
    my ($self) = @_;

    return $self->{'_utils'}->homedir();
}

sub extractdir {
    my ($self) = @_;
    return $self->{'_archive_manager'}->trusted_archive_contents_dir();
}

sub archive_manager {
    my ($self) = @_;

    return $self->{'_archive_manager'};
}

sub prehook {

}

sub posthook {

}

sub utils {
    my ($self) = @_;
    return $self->{'_utils'};
}

sub out {
    my ( $self, @opts ) = @_;
    return $self->{'_utils'}->out(@opts);
}

sub warn {
    my ( $self, @opts ) = @_;

    return $self->{'_utils'}->warn(@opts);
}

sub start_action {
    my ( $self, @opts ) = @_;

    return $self->{'_utils'}->start_action(@opts);
}

sub debug {
    my ( $self, @opts ) = @_;
    return $self->{'_utils'}->debug(@opts);
}

sub restore {
    my ($self) = @_;

    if ( $self->{'_utils'}->is_unrestricted_restore() ) {
        return $self->unrestricted_restore();
    }

    if ( !$self->can('restricted_restore') ) {
        my $module = ref $self;
        $module =~ s{\A.*::}{};

        $self->{'_utils'}->add_skipped_item( _locale()->maketext( 'Restricted restorations do not allow running the “[_1]” module.', $module ) );
        return 1;
    }

    return $self->restricted_restore();
}

sub disable_options {
    return ['all'];
}

sub failure_is_fatal { return 0 }

sub get_fallback_new_owner {
    return $ENV{'REMOTE_USER'} || 'root';
}

sub new_owner ($self) {

    return $self->{'_new_owner'} if $self->{'_new_owner'};

    ## Case 32964: if the owner of the transferring account exists on this system and is a
    ##   reseller, then run create account from the perspective of that reseller (instead of
    ##   the currently running reseller).
    my $createacct_owner = $self->get_fallback_new_owner();

    my $owner_from_package = $self->{'_utils'}->owner();

    if ($owner_from_package) {

        my $is_reseller = Cpanel::Reseller::isreseller($owner_from_package);

        if ( !$is_reseller ) {

            # If the reseller doesn't exist we
            # reset the cache because the reseller might have restored in another process.
            Cpanel::Reseller::Cache::reset_cache($owner_from_package);
            $is_reseller = Cpanel::Reseller::isreseller($owner_from_package);

        }

        #This may be superfluous..?
        $is_reseller &&= Cpanel::AcctUtils::Account::accountexists($owner_from_package);

        if ($is_reseller) {
            $createacct_owner = $owner_from_package;
        }
        elsif ( !$self->utils()->is_unrestricted_restore() ) {

            # We allow unrestricted restorations to create accounts
            # owned by nonexistent resellers. This is to facilitate a
            # workflow where owned accounts are transferred prior to
            # the account’s owner.
            $self->utils()->add_skipped_item( $self->_locale()->maketext( 'The user, “[_1]”, that owns the account in this backup is not a reseller on this system. Because of this, “[_2]” will own this restored account instead.', $owner_from_package, $createacct_owner ) );
        }
    }

    return ( $self->{'_new_owner'} = $createacct_owner );
}

sub get_summary { return ['Implementor Error: The summary for this module is missing.']; }

sub get_notes { return undef; }

sub get_restricted_available { return 0; }

sub get_restricted_summary { return undef; }

# for mocking
sub _safe_run_errors {
    my ( $self, @cmd ) = @_;

    return Cpanel::SafeRun::Errors::saferunallerrors(@cmd);
}

my $locale;

sub _locale {
    my ($self) = @_;
    return $locale ||= Cpanel::Locale->get_handle();
}

###########################################################################
#
# Method:
#   _set_cpuser_keys_to_default
#
# Description:
#   This function sets certain, passed in, keys in a user's CPUSER data to the string literal 'default'.
#   Currently, the literal 'default' is all the function is required to do as it's uses are only in the
#   FeatureList and Package restore modules. If there comes a need to expand it to set value to the keys'
#   default, then please do.
#
# Parameters:
#   $self - The class.
#   $user - The username of the account for which to change the CPUSER keys to 'default'.
#   $keys - An array reference made up of CPUSER keys to set to 'default'.
#
# Exceptions:
#   die - Cpanel::Config::CpUserGuard::save can die if the CPUSER data cannot be saved.
#   Cpanel::Exception::IO::FileWriteError - Thrown if saving the CPUSER data fails.
#
# Returns:
#   The method returns 1 on success or an exception if it failed.
#
sub _set_cpuser_keys_to_default {
    my ( $self, $user, $keys ) = @_;

    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    my $cpuser_data  = $cpuser_guard->{'data'};

    for my $key (@$keys) {
        $cpuser_data->{$key} = 'default';
    }

    if ( !$cpuser_guard->save() ) {

        # save doesn't return it's reason, so it's a bit hard to tell what happened without
        # looking at the log.
        die Cpanel::Exception::create( 'IO::FileWriteError', 'The system failed to set the [asis,CpUser] data keys [list_and_quoted,_1] to default for the user “[_2]”.', [ $keys, $user ] );
    }

    return 1;
}

1;
