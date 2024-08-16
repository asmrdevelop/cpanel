package Cpanel::DKIM::Propagate::Data;

# cpanel - Cpanel/DKIM/Propagate/Data.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::Propagate::Data

=head1 SYNOPSIS

    Cpanel::DKIM::Propagate::Data::add(
        'my.worker.hostname',
        'userdomain.tld',
        sub { ... },
    );

    Cpanel::DKIM::Propagate::Data::process_propagations( sub { ... } );

=head1 DESCRIPTION

This is the datastore logic for DKIM key propagations:
what adds a propagation to the datastore and what harvests those
propagations and sends them to a callback that does the actual work.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::DKIM::Propagate::DB ();
use Cpanel::SQLite::Savepoint   ();

our $_CHUNK_SIZE = 100;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 add( $WORKER_HOSTNAME, $DOMAIN, $TODO_CR )

Adds an entry to the datastore for the given $WORKER_HOSTNAME, $DOMAIN,
and $KEY_PEM and executes $TODO_CR immediately prior to committing
the changes to the datastore.

=cut

sub add {
    my ( $hostname, $domain, $todo_cr ) = @_;

    my $dbh = Cpanel::DKIM::Propagate::DB->dbconnect();

    my $save = Cpanel::SQLite::Savepoint->new($dbh);

    try {
        $dbh->do( 'REPLACE INTO queue (worker_alias, domain) VALUES (?, ?)', undef, $hostname, $domain );

        $todo_cr->();

        $save->release();
    }
    catch {
        $save->rollback();

        die "Failed to add “$domain” to “$hostname”’s DKIM propagation: $_";
    };

    return;
}

#----------------------------------------------------------------------

=head2 process_propagations( $ON_EACH_CHUNK_CR )

This fetches the datastore’s contents and feeds them into
$ON_EACH_CHUNK_CR in chunks.

Arguments given to $ON_EACH_CHUNK_CR are:

=over

=item * the worker node hostname

=item * a hash reference of domain => DKIM key

=back

If $ON_EACH_CHUNK_CR returns normally, then the DB entries for each
domain are deleted from the DB; otherwise, the DB entries remain
in the DB, and a warning is thrown about the failure.

Nothing is returned.

=cut

sub process_propagations {
    my ($ON_EACH_CHUNK_CR) = @_;

    my $dbh = Cpanel::DKIM::Propagate::DB->dbconnect();

    # A transaction before we read the DB.
    my $outer_save = Cpanel::SQLite::Savepoint->new($dbh);

    my $hostname_rows_hr = _get_all($dbh);

    require Cpanel::DKIM::Load;

    local $@;

    for my $hostname ( keys %$hostname_rows_hr ) {
        my %domain_key;

        for my $row ( @{ $hostname_rows_hr->{$hostname} } ) {
            my $key_pem = eval { Cpanel::DKIM::Load::get_private_key_if_exists( $row->{'domain'} ); };

            # Don’t interpret a failure to load a key as nonexistence.
            do { warn; next } if $@;

            $domain_key{ $row->{'domain'} } = $key_pem;
        }

        # sort facilitates testing
        my @domains = sort keys %domain_key;

        while ( my @chunk = splice( @domains, 0, $_CHUNK_SIZE ) ) {
            my $chunk_save = Cpanel::SQLite::Savepoint->new($dbh);

            my %chunk_domain_key = %domain_key{@chunk};

            my $ph = join( ',', ('?') x @chunk );

            try {
                $dbh->do( "DELETE FROM queue WHERE domain IN ($ph)", undef, @chunk );

                try {
                    $ON_EACH_CHUNK_CR->( $hostname, \%chunk_domain_key );

                    $chunk_save->release();
                }
                catch {
                    warn "Failed to propagate DKIM to $hostname: $_ (@chunk)";
                };
            }
            catch {
                warn "Failed to delete DB entries: $_ (@chunk)";
            };
        }
    }

    $outer_save->release();

    return;
}

# called from tests
sub _get_all {
    my ($dbh) = @_;

    # NOTE: We only use `domain`, so it’d be ideal just to return that.
    # If we make substantive changes here we should make that improvement.
    my $rows_ar = $dbh->selectall_arrayref( 'SELECT * from queue', { Slice => {} } );

    my %worker_rows;

    push @{ $worker_rows{ $_->{'worker_alias'} } }, $_ for @$rows_ar;

    return \%worker_rows;
}

1;
