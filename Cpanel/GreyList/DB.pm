package Cpanel::GreyList::DB;

# cpanel - Cpanel/GreyList/DB.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DBI::SQLite ();

sub new {
    my ( $class, $db_file, $opts ) = @_;
    $opts = {} if !$opts || 'HASH' ne ref $opts;
    $opts->{'db'} = $db_file;

    # TODO: handle case where $db_file is not writable.
    if ( !-e $db_file ) {
        open my $fh, '>', $db_file or die "Unable to create DB: $!\n";    #touch
        close $fh;
        chmod 0600, $db_file;
    }

    # sets RaiseError and handles errors via Cpanel::Exception for us.
    my $dbh  = Cpanel::DBI::SQLite->connect($opts);
    my $self = bless { 'dbh' => $dbh }, $class;

    # If the DB hasn't been initialized yet - i.e., this is the first
    # instance the SQlite DB is used - then initialize it as part of
    # the object creation.
    $self->initialize_db() if !-s $db_file;
    return $self;
}

sub has_existing_deferred_entry {
    my ( $self, $data ) = @_;
    return if !$data || 'ARRAY' ne ref $data || scalar @{$data} != 3;

    my $sth = $self->{'dbh'}->prepare("SELECT id FROM triplets_seen WHERE sender_ip = ? AND from_addr = ? AND to_addr = ? AND record_exp_time > datetime('now','localtime') LIMIT 1;");
    $sth->execute( @{$data} );
    my $result = $sth->fetchrow_hashref;
    return $result->{'id'};
}

sub has_initial_block_expired {
    my ( $self, $record_id ) = @_;
    return if !$record_id || ref $record_id;

    # If the record's block_exp_time is less than now, then the initial block has expired.
    my $count = $self->{'dbh'}->selectrow_array( "SELECT COUNT(*) FROM triplets_seen WHERE id = (? + 0) AND block_exp_time < datetime('now','localtime');", undef, $record_id );
    return $count ? $count : 0;
}

sub insert_new_deferred_entry {
    my ( $self, $data, $CONFIG ) = @_;
    return if !$data || 'ARRAY' ne ref $data || scalar @{$data} != 3;

    require Time::Piece;
    my $curtime            = Time::Piece->new();
    my $initial_block_time = $curtime + ( $CONFIG->{'initial_block_time_mins'} * 60 );
    my $must_try_time      = $curtime + ( $CONFIG->{'must_try_time_mins'} * 60 );
    my $record_exp_time    = $curtime + ( $CONFIG->{'record_exp_time_mins'} * 60 );

    my $sth = $self->{'dbh'}->prepare("INSERT INTO triplets_seen (sender_ip, from_addr, to_addr, block_exp_time, must_retry_by, record_exp_time) VALUES ( ?, ?, ?, ?, ?, ? );");

    # Need to use strftime here to format the datetime strings properly, because sqlite doesn't
    # understand the $t->datetime format ('T' is the separator used in that standard instead of a space).
    $sth->execute( @{$data}, $initial_block_time->strftime("%Y-%m-%d %H:%M:%S"), $must_try_time->strftime("%Y-%m-%d %H:%M:%S"), $record_exp_time->strftime("%Y-%m-%d %H:%M:%S") );

    return 1;
}

sub is_trusted_host {
    my ( $self, $ip ) = @_;
    return if !$ip || ref $ip;

    my $count = $self->{'dbh'}->selectrow_array( "SELECT COUNT(*) FROM trusted_hosts WHERE host_ip_start <= ? and ? <= host_ip_end;", undef, $ip, $ip );
    return $count;
}

sub is_trusted_common_mail_provider {
    my ( $self, $ip ) = @_;
    return if !$ip || ref $ip;

    my $count = $self->{'dbh'}->selectrow_array( "SELECT COUNT(*) FROM common_mail_provider_ips WHERE host_ip_start <= ? and ? <= host_ip_end AND is_trusted = 1;", undef, $ip, $ip );
    return $count;
}

sub is_trusted_range {
    my ( $self, $data_ar ) = @_;
    return if !$data_ar || 'ARRAY' ne ref $data_ar || scalar @{$data_ar} != 2;

    my $count = $self->{'dbh'}->selectrow_array( "SELECT COUNT(*) FROM trusted_hosts WHERE host_ip_start <= ? and ? <= host_ip_end;", undef, @{$data_ar} );
    return $count ? $count : 0;
}

sub create_trusted_host {
    my ( $self, $data ) = @_;
    return if !$data || 'ARRAY' ne ref $data || scalar @{$data} != 3;

    my $sth = $self->{'dbh'}->prepare("INSERT INTO trusted_hosts (host_ip_start, host_ip_end, comment) VALUES ( ?, ?, ? );");
    $sth->execute( @{$data} );
    return if not scalar $sth->rows;

    $sth = $self->{'dbh'}->prepare("SELECT * FROM trusted_hosts WHERE host_ip_start = ? AND host_ip_end = ?;");
    $sth->execute( $data->[0], $data->[1] );
    return $sth->fetchrow_hashref();
}

sub read_trusted_hosts {
    my $self = shift;

    my $sth = $self->{'dbh'}->prepare('SELECT * from trusted_hosts;');
    $sth->execute();

    my $results = $sth->fetchall_arrayref( {} );
    return $results;
}

sub delete_trusted_host {
    my ( $self, $data ) = @_;
    return if !$data || 'ARRAY' ne ref $data || scalar @{$data} != 2;

    my $sth = $self->{'dbh'}->prepare("DELETE FROM trusted_hosts WHERE host_ip_start = ? AND host_ip_end = ?;");
    $sth->execute( @{$data} );

    return ( scalar $sth->rows ? 1 : 0 );
}

sub purge_old_records {
    my $self = shift;

    # Remove all records from triplets_seen that meet the following conditions:
    # - The record_exp_time has been reached. OR
    # - We are past the 'must_retry_by' time, but still have not accepted any emails for the triplet
    my $sth = $self->{'dbh'}->prepare("DELETE FROM triplets_seen WHERE record_exp_time < datetime('now','localtime') OR ( must_retry_by < datetime('now','localtime') AND accepted_count = 0 );");
    $sth->execute();

    return scalar $sth->rows;
}

sub increment_accepted_counter {
    my ( $self, $record_id ) = @_;
    return if !$record_id || ref $record_id;

    $self->{'dbh'}->do( "UPDATE triplets_seen SET accepted_count = accepted_count + 1 WHERE id = ?", undef, $record_id );
    return 1;
}

sub increment_deferred_counter {
    my ( $self, $record_id ) = @_;

    $self->{'dbh'}->do( "UPDATE triplets_seen SET deferred_count = deferred_count + 1 WHERE id = ?", undef, $record_id );
    return 1;
}

sub get_deferred_list {
    my ( $self, $data_ar ) = @_;
    $data_ar = [] if !$data_ar || 'ARRAY' ne ref $data_ar;

    _sanitize_args($data_ar);
    my ( $limit, $offset, $order_by, $order, $is_filter, $filter_value ) = @{$data_ar};

    my $sth;
    if ( $is_filter && defined $filter_value && length($filter_value) > 0 ) {

        # If filter_value contains non-ascii chars, then assume it's an ip and try for an absolute match.
        # Otherwise, assume its an email search being requested, and allow for partial matches.
        my $search_term = ( $filter_value !~ m/^[[:ascii:]]+$/ ) ? $filter_value : "%${filter_value}%";

        # Can not use placeholders for the "order by" values, so we alter the sql query as needed.
        $sth = $self->{'dbh'}->prepare( 'SELECT * FROM triplets_seen WHERE sender_ip = ? OR from_addr LIKE ? OR to_addr LIKE ? ORDER BY ' . "$order_by $order" . ' LIMIT ? OFFSET ?;' );
        $sth->execute( $search_term, $search_term, $search_term, $limit, $offset );
    }
    else {
        $sth = $self->{'dbh'}->prepare( 'SELECT * FROM triplets_seen ORDER BY ' . "$order_by $order" . ' LIMIT ? OFFSET ?;' );
        $sth->execute( $limit, $offset );
    }

    my $results = $sth->fetchall_arrayref( {} );
    return wantarray ? ( $results, $self->_get_current_deferred_list_count($data_ar) ) : $results;
}

sub is_greylisting_enabled {
    my ( $self, $domain ) = @_;

    # In case they get email on a subdomain of an 'opted out' domain -
    # i.e., the receiving email address is "email@sub.domain.name" on a server where
    # domain.name has opted out of greylisting.
    my $root_domain = '';
    eval {
        require Mail::SpamAssassin::RegistryBoundaries;
        $root_domain = Mail::SpamAssassin::RegistryBoundaries->new( { ignore_site_cf_files => 1 } )->trim_domain($domain);
    };
    my $count = $self->{'dbh'}->selectrow_array( "SELECT COUNT(*) FROM opt_out_domains WHERE domain_name = ? OR domain_name = ?;", undef, $domain, $root_domain );

    # if there is an entry for the domain in the opt_out table, then greylisting for that domain is disabled
    return $count ? 0 : 1;
}

sub disable_opt_out_for_domains {
    my ( $self, $domains ) = @_;
    $domains = [] if !$domains || 'ARRAY' ne ref $domains;
    return if !scalar @{$domains};

    my $sth = $self->{'dbh'}->prepare("DELETE FROM opt_out_domains WHERE domain_name = ?");
    foreach my $domain (@$domains) {
        $sth->execute($domain);
    }

    return 1;
}

sub enable_opt_out_for_domains {
    my ( $self, $domains ) = @_;
    $domains = [] if !$domains || 'ARRAY' ne ref $domains;
    return if !scalar @{$domains};

    $self->{'dbh'}->{AutoCommit} = 0;
    my $sth = $self->{'dbh'}->prepare("INSERT INTO opt_out_domains (domain_name) VALUES (?)");
    foreach my $domain (@$domains) {
        $sth->execute($domain);
    }
    $self->{'dbh'}->commit;
    $self->{'dbh'}->{AutoCommit} = 1;

    return 1;
}

### Common Mail Providers

sub get_common_mail_providers {
    my $self = shift;

    my $sth = $self->{'dbh'}->prepare("SELECT * FROM common_mail_providers;");
    $sth->execute();
    return $sth->fetchall_hashref('provider_tag');
}

sub add_entries_for_common_mail_provider {

    # $data must be an array of arrays, containing the binary for the ip addresses:
    # [
    #     [ $start_address_bin, $end_address_bin ]
    # ]
    my ( $self, $provider, $data ) = @_;
    return if !length $provider;
    return if !$data || 'ARRAY' ne ref $data;

    my $provider_id = $self->{'dbh'}->selectrow_array( "SELECT id FROM common_mail_providers WHERE provider_tag = ?;", undef, $provider );
    return if not $provider_id;

    my $sth = $self->{'dbh'}->prepare("INSERT INTO common_mail_provider_ips (host_ip_start, host_ip_end, provider_id) VALUES ( ?, ?, ? );");

    my $ips_added = 0;
    foreach my $ip ( @{$data} ) {
        $sth->execute( @{$ip}, $provider_id );
        $ips_added++;
    }

    return $ips_added;
}

sub delete_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if !length $provider;

    my $provider_id = $self->{'dbh'}->selectrow_array( "SELECT id FROM common_mail_providers WHERE provider_tag = ?;", undef, $provider );
    return if not $provider_id;

    my $sth = $self->{'dbh'}->prepare("DELETE FROM common_mail_provider_ips WHERE provider_id = ?;");
    $sth->execute($provider_id);
    my $records_removed = scalar $sth->rows;

    $sth = $self->{'dbh'}->prepare("UPDATE common_mail_providers SET is_trusted = 0 WHERE id = ?;");
    $sth->execute($provider_id);
    return $records_removed;
}

sub trust_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if not length $provider;

    my $provider_id = $self->{'dbh'}->selectrow_array( "SELECT id FROM common_mail_providers WHERE provider_tag = ?;", undef, $provider );
    return if not $provider_id;

    my $sth = $self->{'dbh'}->prepare("UPDATE common_mail_provider_ips SET is_trusted = 1 WHERE provider_id = ?;");
    $sth->execute($provider_id);
    my $records_altered = scalar $sth->rows;

    $sth = $self->{'dbh'}->prepare("UPDATE common_mail_providers SET is_trusted = 1 WHERE id = ?;");
    $sth->execute($provider_id);
    return $records_altered;
}

sub untrust_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if not length $provider;

    my $provider_id = $self->{'dbh'}->selectrow_array( "SELECT id FROM common_mail_providers WHERE provider_tag = ?;", undef, $provider );
    return if not $provider_id;

    my $sth = $self->{'dbh'}->prepare("UPDATE common_mail_provider_ips SET is_trusted = 0 WHERE provider_id = ?;");
    $sth->execute($provider_id);
    my $records_altered = scalar $sth->rows;

    $sth = $self->{'dbh'}->prepare("UPDATE common_mail_providers SET is_trusted = 0 WHERE id = ?;");
    $sth->execute($provider_id);
    return $records_altered;
}

sub list_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if not length $provider;

    my $provider_id = $self->{'dbh'}->selectrow_array( "SELECT id FROM common_mail_providers WHERE provider_tag = ?;", undef, $provider );
    return if not $provider_id;

    my $sth = $self->{'dbh'}->prepare("SELECT * FROM common_mail_provider_ips WHERE provider_id = ?");
    $sth->execute($provider_id);
    return $sth->fetchall_arrayref( {} );
}

sub add_mail_provider {
    my ( $self, $provider, $display_name, $last_updated ) = @_;
    return if !( length $provider && length $display_name );
    $last_updated //= time();

    my $sth = $self->{'dbh'}->prepare("INSERT INTO common_mail_providers (provider_tag, display_name, last_updated) VALUES ( ?, ?, ? );");
    $sth->execute( $provider, $display_name, $last_updated );
    return 1;
}

sub remove_mail_provider {
    my ( $self, $provider ) = @_;
    return if !length $provider;

    $self->delete_entries_for_common_mail_provider($provider);

    my $sth = $self->{'dbh'}->prepare("DELETE FROM common_mail_providers WHERE provider_tag = ?;");
    $sth->execute($provider);

    return 1;
}

sub rename_mail_provider {
    my ( $self, $old_provider, $new_provider ) = @_;
    return unless length $old_provider && length $new_provider;

    my $sth = $self->{'dbh'}->prepare("UPDATE common_mail_providers SET provider_tag = ? WHERE provider_tag = ?");
    $sth->execute( $new_provider, $old_provider );

    return 1;
}

sub bump_last_updated_for_mail_provider {
    my ( $self, $provider, $last_updated ) = @_;
    return if !length $provider;
    $last_updated //= time();

    my $sth = $self->{'dbh'}->prepare("UPDATE common_mail_providers SET last_updated = ? WHERE provider_tag = ?");
    $sth->execute( $last_updated, $provider );
    return 1;
}

sub update_display_name_for_mail_provider {
    my ( $self, $provider, $display_name ) = @_;
    return unless length $provider && length $display_name;

    my $sth = $self->{'dbh'}->prepare("UPDATE common_mail_providers SET display_name = ? WHERE provider_tag = ?");
    $sth->execute( $display_name, $provider );
    return 1;
}

### Common Mail Providers -- end

sub initialize_db {
    my ( $self, $force ) = @_;

    $self->_create_triplets_seen_tbl($force);
    $self->_create_trusted_hosts_tbl($force);
    $self->_create_common_mail_providers_tbls($force);
    $self->_create_opt_out_domains_tbl($force);
    $self->_create_stats_tbl($force);
    return 1;
}

sub _create_triplets_seen_tbl {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS triplets_seen;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS triplets_seen (
    id INTEGER PRIMARY KEY,
    sender_ip VARBINARY(16),
    from_addr VARCHAR(254),
    to_addr VARCHAR(254),
    deferred_count BIGINT DEFAULT 1,
    accepted_count BIGINT DEFAULT 0,
    create_time DATETIME DEFAULT ( DATETIME ( 'now', 'localtime' ) ),
    block_exp_time DATETIME,
    must_retry_by DATETIME,
    record_exp_time DATETIME
);
END_OF_SQL
    );

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE INDEX IF NOT EXISTS triplet_index ON triplets_seen(sender_ip, from_addr, to_addr);
END_OF_SQL
    );

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TRIGGER IF NOT EXISTS update_stats
AFTER DELETE ON triplets_seen FOR EACH ROW
BEGIN
    UPDATE stats SET
        triplets_deferred_count = triplets_deferred_count + ( ( old.deferred_count > old.accepted_count ) + 0 ),
        possible_spam_count = possible_spam_count + old.deferred_count
    WHERE id = 1;
END;
END_OF_SQL
    );
    return 1;
}

sub _create_trusted_hosts_tbl {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS trusted_hosts;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS trusted_hosts (
    id INTEGER PRIMARY KEY,
    host_ip_start VARBINARY(16),
    host_ip_end VARBINARY(16),
    comment VARCHAR(254) DEFAULT NULL,
    create_time DATETIME DEFAULT ( DATETIME ( 'now', 'localtime' ) ),
    UNIQUE (host_ip_start, host_ip_end) ON CONFLICT REPLACE
);
END_OF_SQL
    );
    return 1;
}

sub _create_common_mail_providers_tbls {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS common_mail_providers;')    if $force;
    $self->{'dbh'}->do('DROP TABLE IF EXISTS common_mail_provider_ips;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS common_mail_providers (
    id INTEGER PRIMARY KEY,
    provider_tag TEXT,
    display_name TEXT,
    last_updated INTEGER DEFAULT ( strftime( '%s', 'now' ) ),
    is_trusted INTEGER DEFAULT 0,
    UNIQUE (provider_tag) ON CONFLICT REPLACE
);
END_OF_SQL
    );

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS common_mail_provider_ips (
    host_ip_start VARBINARY(16),
    host_ip_end VARBINARY(16),
    provider_id INTEGER,
    create_time DATETIME DEFAULT ( DATETIME ( 'now', 'localtime' ) ),
    is_trusted INTEGER DEFAULT 0,
    UNIQUE (host_ip_start, host_ip_end, provider_id) ON CONFLICT REPLACE,
    FOREIGN KEY(provider_id) REFERENCES common_mail_providers(id)
);
END_OF_SQL
    );
    return 1;
}

sub _create_opt_out_domains_tbl {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS opt_out_domains;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS opt_out_domains (
    id INTEGER PRIMARY KEY,
    domain_name VARCHAR(255),
    create_time DATETIME DEFAULT ( DATETIME ( 'now', 'localtime' ) ),
    UNIQUE (domain_name) ON CONFLICT REPLACE
);
END_OF_SQL
    );
    return 1;
}

sub _create_stats_tbl {
    my ( $self, $force ) = @_;

    $self->{'dbh'}->do('DROP TABLE IF EXISTS stats;') if $force;

    $self->{'dbh'}->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS stats (
    id INTEGER PRIMARY KEY,
    triplets_deferred_count BIGINT DEFAULT 0,
    possible_spam_count BIGINT DEFAULT 0
);
END_OF_SQL
    );

    $self->{'dbh'}->do("INSERT OR IGNORE INTO stats VALUES (1, 0, 0);");

    return 1;
}

sub _get_current_deferred_list_count {
    my ( $self, $data_ar ) = @_;

    my ( $is_filter, $filter_value ) = @{$data_ar}[ 4, 5 ];

    my $count;
    if ( $is_filter && defined $filter_value && length($filter_value) > 0 ) {
        my $search_term = ( $filter_value !~ m/^[[:ascii:]]+$/ ) ? $filter_value : "%${filter_value}%";
        $count = $self->{'dbh'}->selectrow_array( 'SELECT COUNT(*) FROM triplets_seen WHERE sender_ip = ? OR from_addr LIKE ? OR to_addr LIKE ?;', undef, $search_term, $search_term, $search_term );
    }
    else {
        $count = $self->{'dbh'}->selectrow_array('SELECT COUNT(*) FROM triplets_seen;');
    }

    return $count ? $count : 0;
}

sub _sanitize_args {
    my $data_ar = shift;
    $data_ar->[0] = 20    if !$data_ar->[0] || $data_ar->[0] !~ m/^\d+$/;
    $data_ar->[1] = 0     if !$data_ar->[1] || $data_ar->[1] !~ m/^\d+$/;
    $data_ar->[2] = 'id'  if !$data_ar->[2] || !grep { $_ eq $data_ar->[2] } qw(sender_ip from_addr to_addr deferred_count accepted_count create_time block_exp_time must_retry_by record_exp_time);
    $data_ar->[3] = 'ASC' if !$data_ar->[3] || $data_ar->[3] !~ m/^(ASC|DESC)$/;
    $data_ar->[4] = 0     if !$data_ar->[4] || $data_ar->[4] !~ m/^\d+$/;
    $data_ar->[5] = ''    if !$data_ar->[5];
    return 1;
}

1;
