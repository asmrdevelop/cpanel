package Cpanel::SSL::Auto::Problems;

# cpanel - Cpanel/SSL/Auto/Problems.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Problems - per-FQDN AutoSSL problem tracking

=head1 SYNOPSIS

    my $prob_obj = Cpanel::SSL::Auto::Problems->new();

    my $recs_ar = $prob_obj->get_for_user('theuser');

    $prob_obj->set( 'theuser', '1971-01-02T03:04:05Z', {
        'domain.tld' => 'This is why',
        'domain2.tld' => 'we can’t have nice things.',
    } );

    $recs_count = $prob_obj->unset_domain('domain.tld');

    $recs_count = $prob_obj->purge_user('theuser');

    $recs_count = $prob_obj->purge_expired();

=head1 DESCRIPTION

This datastore tracks each domain’s AutoSSL problems. For now the problems
that it tracks are only those that concern DCV; however, it’s possible that
other kinds of problems may be tracked here in the future.

=head1 METHODS

=cut

use strict;
use warnings;

use Cpanel::SQLite::Compat       ();
use Cpanel::SSL::Auto::Constants ();
use Cpanel::Time::ISO            ();

#Order is relevant to logic down below.
use constant _FIELD_NAMES => qw(
  username
  log
  domain
  problem
);

use constant SQLITE_MAX_VARIABLE_NUMBER => 999;

use constant {
    _FIELDS_SQL => join( ',', _FIELD_NAMES ),

    #SQLite does limit query size, so we need to enforce a bit of sanity.
    _INSERT_CHUNK_SIZE => int( SQLITE_MAX_VARIABLE_NUMBER / scalar _FIELD_NAMES ),
};

=head2 I<CLASS>->new()

Instantiates the object.

=cut

sub new {
    my ($class) = @_;

    my $self = { _db => "${class}::DB"->dbconnect() };

    #This DB was errantly created non-WAL for a while;
    #this ensures that that’s fixed.
    Cpanel::SQLite::Compat::upgrade_to_wal_journal_mode_if_needed( $self->{'_db'} );

    return bless $self, $class;
}

=head2 $records_ar = I<OBJ>->get_for_user( USERNAME )

Returns a reference to an array of hashes. Each hash contains:

=over

=item * C<domain> - The domain (e.g., C<foo.com>, C<cpanel.foo.com>)

=item * C<problem> - A text description of the problem.

=item * C<log> - The name of the AutoSSL log where the problem happened.
This will be an ISO/Zulu-format timestamp.

=item * C<time> - The time (in ISO/Zulu format) when the problem happened.

=back

Note that the username is not contained in the return because it’s part
of the function call; there’s no need to provide what was already given.

=cut

sub get_for_user {
    my ( $self, $username ) = @_;

    return $self->{'_db'}->selectall_arrayref(
        'SELECT log, domain, problem, time FROM problems WHERE username = ?',
        { Slice => {} },
        $username,
    );
}

#We can add a per-domain query if it’s needed.

=head2 $count = I<OBJ>->set( USERNAME, LOG_NAME, PROBLEMS_HR )

This sets values in the datastore. LOG_NAME is the AutoSSL log name.
PROBLEMS_HR is a hash reference: { DOMAIN => PROBLEM, .. }, where DOMAIN
is the actual FQDN that failed DCV.

The return is the number of records affected by the operation—which
should just be the number of entries in PROBLEMS_HR.

=cut

sub set {
    my ( $self, $username, $log, $problems_hr ) = @_;

    my $fields_str = _FIELDS_SQL;
    my $fields_ph  = '(' . join(
        ',',
        $self->{'_db'}->quote($username),
        $self->{'_db'}->quote($log),
        '?', '?',    #domain, problem
    ) . ')';

    my @domains = keys %$problems_hr;

    my $affected = 0;

    local $self->{'_db'}{'AutoCommit'} = 0;

    while (@domains) {
        my @these_domains = splice( @domains, 0, _INSERT_CHUNK_SIZE );

        my $values_ph = join( ',', ($fields_ph) x @these_domains );

        $affected += $self->{'_db'}->do(
            "REPLACE INTO problems ($fields_str) VALUES $values_ph",
            undef,
            %{$problems_hr}{@these_domains},
        );
    }

    $self->{'_db'}->commit();

    return $affected;
}

=head2 $count = I<OBJ>->unset_domain( DOMAIN )

Remove the datastore entry for the given domain. Returns the
number of entries affected—either 0 or 1.

=cut

sub unset_domain {
    my ( $self, $domain ) = @_;

    return 0 + $self->{'_db'}->do(
        'DELETE FROM problems WHERE domain = ?',
        undef,
        $domain,
    );
}

=head2 $count = I<OBJ>->unset_domains( DOMAINS )

Remove the datastore entry for the given domains. Returns the
number of entries affected.

=cut

sub unset_domains {
    my ( $self, @domains ) = @_;

    my $count = 0;

    while (@domains) {
        my @chunk = splice( @domains, 0, SQLITE_MAX_VARIABLE_NUMBER );

        $count += $self->{'_db'}->do(
            'DELETE FROM problems WHERE domain IN (' . join( ',', ('?') x scalar @chunk ) . ')',
            undef,
            @chunk,
        );
    }

    return $count;
}

=head2 $count = I<OBJ>->purge_user( DOMAIN )

Remove the datastore entries for the given user.
Returns the number of entries affected.

=cut

#“purge” because this can affect multiple rows
sub purge_user {
    my ( $self, $username ) = @_;

    return 0 + $self->{'_db'}->do(
        'DELETE FROM problems WHERE username = ?',
        undef,
        $username,
    );
}

=head2 $count = I<OBJ>->purge_expired()

Remove all datastore entries for logs that are older than
the AutoSSL log TTL (cf. L<Cpanel::SSL::Auto::Constants>).

Returns the number of entries affected.

=cut

sub purge_expired {
    my ($self) = @_;

    my $expired_iso = Cpanel::Time::ISO::unix2iso( time - $Cpanel::SSL::Auto::Constants::LOG_TTL );

    return 0 + $self->{'_db'}->do(
        "DELETE FROM problems WHERE log < ?",
        undef,
        $expired_iso,
    );
}

#----------------------------------------------------------------------
# An internal class meant to distinguish the caller logic from the DB.

package Cpanel::SSL::Auto::Problems::DB;

use parent qw(
  Cpanel::SQLite::AutoRebuildSchemaBase
);

use constant {
    _SCHEMA_NAME    => 'autossl_problems',
    _SCHEMA_VERSION => 1,
    _PATH           => '/var/cpanel/autossl_problems.sqlite'
};

1;
