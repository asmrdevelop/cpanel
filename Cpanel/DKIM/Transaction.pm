package Cpanel::DKIM::Transaction;

# cpanel - Cpanel/DKIM/Transaction.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::Transaction

=head1 SYNOPSIS

    my $xaction = Cpanel::DKIM::Transaction->new();

    $xaction->set_up_user('bob');

    $xaction->set_up_user_domains('jane', ['jane.com', 'store.jane.com']);

=head1 DESCRIPTION

DKIM requires multiple datastores to remain in sync. As of this writing
that includes at least the on-disk key storage, DNS, and (as of v78) the
DKIM validity cache. When altering DKIM for multiple domains in batch,
it is prohibitively expensive to synchronize all of those datastores with
each individual domain’s DKIM changes; we need to save the DNS and validity
cache updates to do in a separate batch.

This module facilitates that.

=head1 ERROR REPORTING

Methods of this class report errors via C<warn()>. If that’s problematic
for your calling context, use C<$SIG{__WARN__}>.

=cut

#----------------------------------------------------------------------

use Cpanel::DKIM                       ();
use Cpanel::DKIM::ValidityCache::Write ();
use Cpanel::ServerTasks                ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new {
    return bless { _commit_domain => {} }, shift;
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->skip_dns_reloads()

Tell the object to forgo DNS reloads for all changes.
(See the C<skipreload> flag for several functions in L<Cpanel::DKIM>.)
Returns the object.

=cut

sub skip_dns_reloads {
    $_[0]->{'_skip_dns_reloads'} = 1;

    return $_[0];
}

#----------------------------------------------------------------------

=head2 $state_hr = I<OBJ>->set_up_user( $USERNAME )

Creates a new key and installs it on all of the user’s domains.

The return is undef if no setup is attempted (e.g., if
if DKIM is not enabled for the user), or
a L<Cpanel::DnsUtils::Install::Result> instance.

=cut

sub set_up_user {
    my ( $self, $username ) = @_;

    return $self->_setup_domain_keys_or_warn(
        user => $username,
    );
}

#----------------------------------------------------------------------

=head2 $state_hr = I<OBJ>->set_up_user_domains( $USERNAME, \@DOMAINS [, $ZONE_OBJ ] )

Creates a new key and installs it on the given @DOMAINS.

$ZONE_OBJ is an optional L<Cpanel::ZoneFile> instance; this allows
the DNS setup logic to forgo a fetch of the zone record.

The return is the same as C<set_up_user()>’s.

=cut

sub set_up_user_domains {
    my ( $self, $username, $domains_ar, $opt_zone_ref ) = @_;

    return $self->_setup_domain_keys_or_warn(
        user       => $username,
        domains_ar => $domains_ar,
        zone_ref   => $opt_zone_ref,
    );
}

#----------------------------------------------------------------------

=head2 $state_hr = I<OBJ>->tear_down_user( $USERNAME )

Tears down DKIM setup for all of $USERNAME’s domains.

The return is the same as C<set_up_user()>’s.

=cut

sub tear_down_user {
    my ( $self, $username ) = @_;

    my ( undef, undef, $state_obj ) = Cpanel::DKIM::remove_user_domain_keys(
        user       => $username,
        skipreload => $self->{'_skip_dns_reloads'},
    );

    _handle_teardown_state_obj($state_obj);

    return $state_obj;
}

#----------------------------------------------------------------------

=head2 $state_hr = I<OBJ>->tear_down_user_domains( $USERNAME, \@DOMAINS )

Tears down DKIM setup for @DOMAINS.

The return is the same as C<set_up_user()>’s.

=cut

# Kinda hacky, but at least it’s constrained.
# The problem is that we use Cpanel::DKIM::setup_domain_keys()
# for individual domains but Cpanel::DKIM::remove_user_domain_keys()
# for users.
our $_SKIP_COMMIT;

sub tear_down_user_domains {
    my ( $self, $username, $domains_ar ) = @_;

    local $_SKIP_COMMIT = 1;

    my $state_obj = $self->_setup_domain_keys_or_warn(
        user       => $username,
        domains_ar => $domains_ar,
        delete     => 1,
    );

    # NB: Following the pattern in Cpanel::DKIM::remove_user_domain_keys(),
    # we delete a key from disk even if its domain’s DNS update failed.
    Cpanel::DKIM::check_and_remove_keys( $domains_ar, $username );

    _handle_teardown_state_obj($state_obj);

    return $state_obj;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->commit()

Perform any actions that are pending as a result of other activity
with this object.

Currently this just means synchronizing the DKIM validity cache.

=cut

sub commit {
    my ($self) = @_;

    if ( my @domains = keys %{ $self->{'_commit_domain'} } ) {

        # Give DNS changes some time to propagate (sync across DNS cluster and/or zone reload) before checking validity of those records.
        Cpanel::ServerTasks::schedule_task( ['DKIMTasks'], 60, "refresh_dkim_validity_cache @domains" );

        %{ $self->{'_commit_domain'} } = ();
    }

    return;
}

#----------------------------------------------------------------------

sub DESTROY {
    my ($self) = @_;

    if ( $self->{'_need_commit'} ) {
        warn "$self: DESTROY without commit()! Fixing …";
        $self->commit();
    }

    return;
}

sub _handle_teardown_state_obj {
    my ($state_hr) = @_;

    $state_hr->for_each_domain(
        sub {
            my ($domain) = @_;

            local $@;
            warn if !eval {
                Cpanel::DKIM::ValidityCache::Write->unset($domain);
                1;
            };
        }
    );

    return;
}

sub _setup_domain_keys_or_warn {
    my ( $self, @args ) = @_;

    my ( $status, $msg, $state_hr ) = Cpanel::DKIM::setup_domain_keys(
        @args,
        skipreload => !!$self->{'_skip_dns_reloads'},
    );

    if ($status) {
        $state_hr->for_each_domain(
            sub {
                my ( $domain, $status, $msg ) = @_;

                if ($status) {
                    if ( !$_SKIP_COMMIT ) {
                        $self->{'_commit_domain'}{$domain} = ();
                    }
                }
                else {
                    warn "$domain: $msg";
                }
            }
        );
    }
    else {
        warn $msg;
    }

    # NB: $status is redundant with $state_hr->{'status'}.
    return $state_hr;
}

1;
