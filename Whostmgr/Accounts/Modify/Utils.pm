package Whostmgr::Accounts::Modify::Utils;

# cpanel - Whostmgr/Accounts/Modify/Utils.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Modify::Utils

=head1 DESCRIPTION

This module houses individual pieces of logic for
L<Whostmgr::Accounts::Modify>.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::Context                   ();
use Cpanel::DB::Map::Reader           ();
use Cpanel::PwCache::Get              ();
use Cpanel::Services::Available       ();
use Cpanel::SpamAssassin::Enable      ();
use Whostmgr::ACLS                    ();
use Whostmgr::Packages::Info::Modular ();
use Whostmgr::Resellers::Check        ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 determine_undo_parameters( $CPUSER_HR, %OPTS )

Returns a hashref that can be given to C<modifyacct()> to undo the
proposed changes.

$CPUSER_HR is a hashref of the user’s cpuser data,
and %OPTS are the full arguments given to C<modifyacct()>.

=cut

# Translate input options to their representation in the cpuser datastore:
use constant _NORMALIZE_OPTS => {
    CPTHEME => 'RS',
    owner   => 'OWNER',
    domain  => 'DOMAIN',
    DNS     => 'DOMAIN',
};

use constant _CPUSER_DEFAULT_ACCEPTED => (
    'MAX_DEFER_FAIL_PERCENTAGE',
    'MAX_EMAIL_PER_HOUR',
);

use constant _UNDO_HAS_SAME_VALUE => (
    'rename_database_objects',
    'remove_missing_extensions',
);

use constant _IGNORE_FOR_UNDO => (
    'user',
    '_PACKAGE_EXTENSIONS',
    'mail_node_alias',
);

use constant _IGNORE_FOR_UNDO_REGEX => (
    qr{^account_enhancements(?:-[0-9]+)?$},
);

sub determine_undo_parameters ( $cpuser_data, %OPTS ) {
    my $username = $cpuser_data->{'USER'};

    my %undo = ( user => $username );

    my @components     = Whostmgr::Packages::Info::Modular::get_enabled_components();
    my %name_component = map { $_->name_in_api() => $_ } @components;

  OPTNAME:
    for my $optname ( keys %OPTS ) {
        next if grep { $_ eq $optname } _IGNORE_FOR_UNDO();
        next if grep { $optname =~ m{$_} } _IGNORE_FOR_UNDO_REGEX();

        if ( $optname eq 'newuser' ) {
            @undo{ 'user', 'newuser' } = ( $OPTS{'newuser'}, $username );
        }
        elsif ( $optname eq 'domain' || $optname eq 'DNS' ) {
            $undo{$optname} = $cpuser_data->{'DOMAIN'};
        }
        elsif ( $optname eq 'shell' || $optname eq 'HASSHELL' ) {
            $undo{$optname} = Cpanel::PwCache::Get::getshell($username);
        }
        elsif ( $optname eq 'contactemail' ) {
            $undo{'contactemail'} = join(
                q<>,
                grep { length } @{$cpuser_data}{ 'CONTACTEMAIL', 'CONTACTEMAIL2' },
            );
        }
        elsif ( $optname eq 'owner' || $optname eq 'OWNER' ) {

            # It’s important that we not put an “owner” field unless
            # there was an actual change in ownership. Here’s why:
            #
            # Consider a self-owned reseller “bob”. Now we rename
            # “bob” to “robert”. That modifyacct might include OWNER=bob,
            # which modifyacct interprets as “retain self-ownership”.
            # If we copy OWNER=bob into the undo, though, the undo
            # will look like:
            #
            #   user=robert
            #   newuser=bob
            #   owner=bob
            #
            # … which will fail modifyacct because “bob” doesn’t exist
            # as a reseller until the rename.
            #
            # Arguably, modifyacct should be smart enough to recognize what’s
            # intended when owner == newuser, but it’s also good just to
            # omit OWNER=bob from the undo since it serves no useful purpose.
            #
            # It might be nice, actually, to make this entire function
            # only return things that have actually changed, but it doesn’t
            # seem to make a difference except for this value.

            if ( $cpuser_data->{'OWNER'} ne $OPTS{$optname} ) {
                $undo{'owner'} = $cpuser_data->{'OWNER'};
            }
        }
        elsif ( $optname eq 'spamassassin' ) {
            $undo{'spamassassin'} = Cpanel::SpamAssassin::Enable::is_enabled($username);
        }
        elsif ( $optname eq 'reseller' ) {
            $undo{'reseller'} = Whostmgr::Resellers::Check::is_reseller($username);

            # A sanity check, not intended to run in production.
            if ( !$OPTS{'reseller'} && $undo{'reseller'} ) {
                die 'I can’t undo an un-reseller-ification!';
            }
        }
        elsif ( $optname eq 'QUOTA' ) {
            $undo{'QUOTA'} = get_current_quota($username);
        }
        elsif ( grep { $optname eq $_ } _UNDO_HAS_SAME_VALUE() ) {
            $undo{$optname} = $OPTS{$optname};
        }
        elsif ( $optname eq 'MAXMONGREL' ) {

            # NB: As of November 2019, we could also set 0 here to achieve
            # the same effect; however, that’s a bit weird and definitely
            # inconsistent with the two other meanings of “0” (literal 0,
            # or unlimited) that we usually use, so let’s avoid potential
            # problems down the road.
            $undo{'MAXMONGREL'} = $cpuser_data->{'MAXMONGREL'} // do {
                require Cpanel::RoR;
                Cpanel::RoR::get_default_max_running();
            };
        }
        elsif ( my $component = $name_component{$optname} ) {
            $undo{$optname} = $cpuser_data->{ $component->name_in_cpuser() };
        }
        else {
            my $effective_optname = _NORMALIZE_OPTS()->{$optname} // $optname;

            if ( exists $cpuser_data->{$effective_optname} ) {
                $undo{$effective_optname} = $cpuser_data->{$effective_optname};
            }
            else {
                if ( grep { $_ eq $effective_optname } _CPUSER_DEFAULT_ACCEPTED() ) {
                    $undo{$effective_optname} = 'default';
                }
                else {
                    warn "Unrecognized modifyacct parameter: “$optname”";
                }
            }
        }
    }

    return \%undo;
}

#----------------------------------------------------------------------

=head2 @renamers = get_renamers( $USERNAME, $CPUSER_OBJ )

Returns the list of names of resellers who can rename the user named
by $USERNAME. $CPUSER_OBJ is as given by C<Cpanel::Config::LoadCpUserFile>.

=cut

sub get_renamers ( $username, $cpuser_hr ) {
    Cpanel::Context::must_be_list();

    # List root first.
    my @can_rename = ('root');

    # As long as the user isn’t self-owning, the OWNER can
    # rename the account.
    if ( $cpuser_hr->{'OWNER'} ne $username ) {
        push @can_rename, $cpuser_hr->{'OWNER'};
    }

    require Cpanel::ArrayFunc::Uniq;
    @can_rename = Cpanel::ArrayFunc::Uniq::uniq(@can_rename);

    return @can_rename;
}

#----------------------------------------------------------------------

sub get_current_quota ($username) {
    require Whostmgr::Quota::User;
    return Whostmgr::Quota::User::get_users_quota_data( $username, { include_mailman => 0, include_sqldbs => 0 } )->{'bytes_limit'} || 0;
}

#----------------------------------------------------------------------

=head2 verify_databases_for_user_rename( $USERNAME )

User renames require updates to databases, e.g., to update grants.
This implements a simple check that requires database connectivity if
the indicated user has databases listed in its DB map.

=cut

sub verify_databases_for_user_rename {
    my ($username) = @_;

    my $dbmap = Cpanel::DB::Map::Reader->new(
        engine => 'mysql',
        cpuser => $username,
    );

    if ( my @d = $dbmap->get_databases() ) {
        _ensure_mysql();
    }

    $dbmap->set_engine('postgresql');

    if ( my @d = $dbmap->get_databases() ) {
        _ensure_postgresql();
    }

    return;
}

#----------------------------------------------------------------------

=head2 @warnings = remove_forbidden_requests( \%CPUSER, \%OPTS )

This removes keys from %OPTS that the calling WHM user is forbidden
to include. Ideally we’d fail the modifyacct request at this point,
but for historical reasons we have to ignore the invalid inputs instead.

=cut

sub remove_forbidden_requests ( $cpuser_data, $opts_hr ) {

    my @warnings;

    if ( !Whostmgr::ACLS::hasroot() ) {
        if ( exists $opts_hr->{'reseller'} ) {
            my $is_reseller = Whostmgr::Resellers::Check::is_reseller( $cpuser_data->{'USER'} );

            if ( !!$opts_hr->{'reseller'} ne !!$is_reseller ) {
                delete $opts_hr->{'reseller'};
                push @warnings, locale()->maketext('You cannot change reseller privileges.');
            }
        }

        my $new_owner = $opts_hr->{'OWNER'} || $opts_hr->{'owner'};
        delete @{$opts_hr}{ 'OWNER', 'owner' };

        if ( $new_owner && $new_owner ne $cpuser_data->{'OWNER'} ) {
            push @warnings, locale()->maketext('You cannot change user ownership.');
        }

        my $warned_backup;

        for my $key (qw( BACKUP  LEGACY_BACKUP )) {
            next if !exists $opts_hr->{$key};

            my $backup_yn = delete $opts_hr->{$key};
            $backup_yn = $backup_yn && $backup_yn ne 'no' && $backup_yn ne 'false';

            if ( !!$backup_yn ne !!$cpuser_data->{$key} && !$warned_backup ) {
                push @warnings, locale()->maketext('You cannot change backup settings.');
                $warned_backup = 1;
            }
        }
    }

    return @warnings;
}

#----------------------------------------------------------------------

=head2 dynamicdns_rename_domain( $DZONE_OBJ, $USERNAME, $OLDNAME, $NEWNAME )

Renames $OLDNAME to $NEWNAME within dynamic DNS.

$DZONE_OBJ is a L<Cpanel::Domain::Zone> instance; $USERNAME is the
user’s name.

=cut

sub dynamicdns_rename_domain ( $domain_zone_obj, $username, $olddomain, $newdomain ) {    ## no critic qw(ManyArgs) - mis-parse
    local ( $@, $! );
    require Cpanel::WebCalls::Datastore::Write;

    my $p = Cpanel::WebCalls::Datastore::Write->new_p( timeout => 30 );
    $p = $p->then(
        sub ($writer) {
            $writer->update_user_entries_data(
                $username,
                sub ( $entry, $updater_cr ) {
                    return if !$entry->isa('Cpanel::WebCalls::Entry::DynamicDNS');

                    my $ddns_domain = $entry->domain();
                    my $ddns_zone   = $domain_zone_obj->get_zone_for_domain($ddns_domain);

                    if ( $ddns_zone eq $olddomain ) {
                        my $new_ddns = $ddns_domain =~ s<\.\Q$olddomain\E\z><.$newdomain>r;

                        $updater_cr->(
                            {
                                domain      => $new_ddns,
                                description => $entry->description(),
                            }
                        );
                    }
                },
            );
        },
    );

    require Cpanel::PromiseUtils;
    Cpanel::PromiseUtils::wait_anyevent($p)->get();

    return;
}

#----------------------------------------------------------------------

# overridden in tests
*_ensure_mysql      = \*Cpanel::Services::Available::ensure_mysql_if_provided;
*_ensure_postgresql = \*Cpanel::Services::Available::ensure_postgresql_if_provided;

#----------------------------------------------------------------------

1;
