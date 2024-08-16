package Cpanel::Hulk::Admin;

# cpanel - Cpanel/Hulk/Admin.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception     ();
use Cpanel::Encoder::Tiny ();
use Cpanel::IP::Convert   ();
use Cpanel::Locale        ();
use Cpanel::Validate::IP  ();

use Try::Tiny;

=head1 NAME

Cpanel::Hulk::Admin

=head1 SYNOPSIS

  use Cpanel::Hulk::Admin     ();
  use Cpanel::Hulk::Admin::DB ();

  my $dbh = Cpanel::Hulk::Admin::DB::get_dbh();

  Cpanel::Hulk::Admin::get_hosts($dbh, ...     );
  Cpanel::Hulk::Admin::set_hosts($dbh, ..., ...);
  Cpanel::Hulk::Admin::add_ip_to_list($dbh, ..., ...);
  Cpanel::Hulk::Admin::remove_ip_from_list($dbh, ..., ...);

=head1 FUNCTIONS

=head2 set_hosts($dbh, $list, $hosts)

  $dbh   - A DBI Database Handle object
  $list  - The name of the list in question, minus "list" -- e.g., "white" if you want "whitelist."
  $hosts - An arrayref or whitespace-delimited list of hosts to replace the existing list.

=cut

sub set_hosts {
    my ( $dbh, $list, $hosts ) = @_;

    my $list_type = $Cpanel::Config::Hulk::LIST_TYPE_VALUES{$list} || die "Invalid list type: $list";
    my %ranges;

    foreach my $line ( ref $hosts ? @{$hosts} : split( /[\r\n]+/, $hosts ) ) {
        $line =~ s/^\s*|\s*$//;
        my ( $ip,            $comment )     = split( m{\s*#\s*}, $line );
        my ( $start_address, $end_address ) = Cpanel::IP::Convert::ip_range_to_start_end_address($ip);
        next if !length $start_address || !length $end_address;
        $ranges{$start_address}{$end_address} = $comment ? substr( $comment, 0, 255 ) : '';    # limit the comment field to 255 characters
    }

    require Cpanel::Hulk::Cache::IpLists;
    Cpanel::Hulk::Cache::IpLists->new->expire_all();
    $dbh->do( 'DELETE FROM ip_lists where TYPE=?;', {}, $list_type );

    my $insert_q = $dbh->prepare("INSERT INTO ip_lists (STARTADDRESS,ENDADDRESS,TYPE,COMMENT) VALUES (?,?,?,?);");
    foreach my $start_address ( sort keys %ranges ) {
        foreach my $end_address ( sort keys %{ $ranges{$start_address} } ) {
            $insert_q->execute( $start_address, $end_address, $list_type, $ranges{$start_address}{$end_address} );
        }
    }

    return $insert_q->finish();
}

=head2 get_hosts($dbh, $list)

  $dbh   - A DBI Database Handle object
  $list  - The name of the list in question, minus "list" -- e.g., "white" if you want "whitelist."
  $want_comments - Return end of line comments

Returns an array ref of strings of IP addresses.

Example: ['1.1.1.1', '2.2.2.2]

=cut

*get_sane_hosts = \&get_hosts;

sub get_hosts {
    my ( $dbh, $list, $want_comments ) = @_;

    my $list_type = $Cpanel::Config::Hulk::LIST_TYPE_VALUES{$list} || die "Invalid list type: $list";
    my $rows;
    try {
        $rows = $dbh->selectall_arrayref( 'SELECT STARTADDRESS, ENDADDRESS, COMMENT from ip_lists where TYPE=? ORDER BY STARTADDRESS;', {}, $list_type );
    }
    catch {
        die Cpanel::Exception->create( "The system failed to fetch [asis,cphulkd] hosts because the “[_1]” table may be corrupted and returned the following error: [_2].", [ 'cphulkd.ip_lists', Cpanel::Exception::get_string($_) ] );
    };

    my @results;
    foreach my $row ( @{$rows} ) {
        my $start_human_readable_address = Cpanel::IP::Convert::binip_to_human_readable_ip( $row->[0] );
        my $end_human_readable_address   = Cpanel::IP::Convert::binip_to_human_readable_ip( $row->[1] );
        my $comment                      = $row->[2];

        if ( $start_human_readable_address eq $end_human_readable_address ) {
            push @results, $start_human_readable_address;
        }
        else {
            push @results, "$start_human_readable_address-$end_human_readable_address";
        }

        if ( length $comment and $want_comments ) {
            $results[-1] .= " # " . $comment;
        }
    }
    return \@results;
}

=head2 add_ip_to_list($dbh, $ip, $list, $comment)

  $dbh      - A DBI Database Handle object
  $ip       - The IP address to add to the list in question.
  $list     - The name of the list in question, minus "list" -- e.g., "white" if you want "whitelist."
  $comment  - A comment

This function adds an IP address or range to a cphulkd white or blacklist.

Note: As of Apr 2014, this function no longer replaces the entire contents of the table just to insert
a row, but instead uses a single INSERT, as one would expect.

=cut

sub list_ip {    #legacy (note the different args order)
    my ( $dbh, $list, $ip, $comment ) = @_;
    return add_ip_to_list( $dbh, $ip, $list, $comment );
}

sub add_ip_to_list {
    my ( $dbh, $ip, $list, $comment ) = @_;
    $comment = $comment ? substr( $comment, 0, 255 ) : '';

    my $list_type = $Cpanel::Config::Hulk::LIST_TYPE_VALUES{$list} || die "Invalid list type: $list";

    my ( $start_address, $end_address ) = _get_ip_range($ip);

    require Cpanel::Hulk::Cache::IpLists;
    Cpanel::Hulk::Cache::IpLists->new->expire_all();
    my $ret;
    try {
        $ret = $dbh->do( 'INSERT INTO ip_lists (STARTADDRESS,ENDADDRESS,TYPE,COMMENT) VALUES (?,?,?,?);', {}, $start_address, $end_address, $list_type, $comment ) ? 1 : 0;
    }
    catch {
        die Cpanel::Exception->create( "The system failed to add an IP address to [asis,cphulkd] hosts because the “[_1]” table may be corrupted and returned the following error: [_2].", [ 'cphulkd.ip_lists', Cpanel::Exception::get_string($_) ] );
    };

    return wantarray ? ( Cpanel::IP::Convert::binip_to_human_readable_ip($start_address), Cpanel::IP::Convert::binip_to_human_readable_ip($end_address) ) : $ret;
}

=head2 remove_ip_from_list($dbh, $ip, $list)

  $dbh   - A DBI Database Handle object
  $ip    - The IP address to remove from the list in question.
  $list  - The name of the list in question, minus "list" -- e.g., "white" if you want "whitelist."

This function removes an IP address or range from a cphulkd white or blacklist.

=cut

sub delist_ip {    #legacy (note the different args order)
    my ( $dbh, $list, $ip ) = @_;
    return remove_ip_from_list( $dbh, $ip, $list );
}

sub remove_ip_from_list {
    my ( $dbh, $ip, $list ) = @_;

    my $list_type = $Cpanel::Config::Hulk::LIST_TYPE_VALUES{$list} || die "Invalid list type: $list";

    my ( $start_address, $end_address ) = _get_ip_range($ip);

    require Cpanel::Hulk::Cache::IpLists;
    Cpanel::Hulk::Cache::IpLists->new->expire_all();

    my $ret;
    try {
        # The unary "+" is used here to disqualify WHERE clause from the "indices optimization". See https://sqlite.org/optoverview.html#uplus
        # This ensures that the DELETE call properly removes entries from the ip_lists table.
        $ret = $dbh->do( 'DELETE FROM ip_lists WHERE STARTADDRESS=? and +ENDADDRESS=? and TYPE=?;', {}, $start_address, $end_address, $list_type ) ? 1 : 0;
    }
    catch {
        die Cpanel::Exception->create( "The system failed to remove an IP address from [asis,cphulkd] hosts because the “[_1]” table may be corrupted and returned the following error: [_2].", [ 'cphulkd.ip_lists', Cpanel::Exception::get_string($_) ] );
    };

    return $ret;
}

sub get_failed_logins {
    my $dbh = shift;

    return _get_logins( $dbh, $Cpanel::Config::Hulk::LOGIN_TYPE_FAILED );
}

sub get_user_brutes {
    my $dbh = shift;

    return _get_logins( $dbh, $Cpanel::Config::Hulk::LOGIN_TYPE_USER_SERVICE_BRUTE );
}

sub get_user_brutes_for_user {
    my ( $dbh, $user ) = @_;

    return _get_logins( $dbh, $Cpanel::Config::Hulk::LOGIN_TYPE_USER_SERVICE_BRUTE, $user );
}

sub get_brutes {
    my $dbh = shift;

    return _get_brutes( $dbh, $Cpanel::Config::Hulk::LOGIN_TYPE_BRUTE );
}

sub get_excessive_brutes {
    my $dbh = shift;

    return _get_brutes( $dbh, $Cpanel::Config::Hulk::LOGIN_TYPE_EXCESSIVE_BRUTE );
}

sub is_ip_whitelisted {
    my ( $dbh, $ip ) = @_;

    my $count;
    try {
        my $binip = Cpanel::IP::Convert::ip2bin16($ip);
        $count = $dbh->selectrow_array( "SELECT COUNT(*) FROM ip_lists WHERE STARTADDRESS <= ? AND ? <= ENDADDRESS;", undef, $binip, $binip );
    }
    catch {
        die Cpanel::Exception->create( "A query on the table “[_1]” produced an error ([_2]). Something might have corrupted this table.", [ 'cphulkd.ip_lists', Cpanel::Exception::get_string($_) ] );
    };

    return $count ? $count : 0;
}

sub _get_brutes {
    my ( $dbh, $login_type ) = @_;

    my $q = $dbh->prepare("SELECT ADDRESS,NOTES,LOGINTIME,EXPTIME,((STRFTIME('%s',EXPTIME,'utc') - STRFTIME('%s','now'))/60) as TIMELEFT FROM login_track where TYPE=? and EXPTIME > DATETIME('now', 'localtime');");
    try {
        $q->execute($login_type);
    }
    catch {
        die Cpanel::Exception->create( "The “[_1]” table seems corrupted, and returned the following error: “[_2]”", [ 'cphulkd.login_track', Cpanel::Exception::get_string($_) ] );
    };

    return _parse_brute_login_results($q);
}

sub _get_logins {
    my ( $dbh, $login_type, $user ) = @_;

    my $q;

    # TIMELEFT is in minutes
    if ( !length $user ) {
        $q = $dbh->prepare("SELECT USER,ADDRESS,AUTHSERVICE,SERVICE,LOGINTIME,EXPTIME,((STRFTIME('%s',EXPTIME,'utc') - STRFTIME('%s','now'))/60) as TIMELEFT FROM login_track where TYPE=? and EXPTIME > DATETIME('now', 'localtime');");
    }
    else {
        $q = $dbh->prepare("SELECT USER,ADDRESS,AUTHSERVICE,SERVICE,LOGINTIME,EXPTIME,((STRFTIME('%s',EXPTIME,'utc') - STRFTIME('%s','now'))/60) as TIMELEFT FROM login_track where TYPE=? and EXPTIME > DATETIME('now', 'localtime') and USER=?;");
    }

    try {
        $q->execute( $login_type, length $user ? ($user) : () );
    }
    catch {
        die Cpanel::Exception->create( "The “[_1]” table seems corrupted, and returned the following error: “[_2]”", [ 'cphulkd.login_track', Cpanel::Exception::get_string($_) ] );
    };

    return _parse_brute_login_results($q);
}

sub _parse_brute_login_results {
    my $q = shift;

    require Cpanel::GeoIPfree;
    my $geo = Cpanel::GeoIPfree->new();
    $geo->Faster();    # ->Faster was actually slower until it was fixed in CPANEL-27702

    my @results;
    my %_country_code_name_cache;
    my %_human_readable_ip_cache;
    my $refs = $q->fetchall_arrayref( {} );
    foreach my $ref (@$refs) {

        my $address  = delete $ref->{'ADDRESS'};
        my $ip       = $_human_readable_ip_cache{$address} ||= Cpanel::IP::Convert::binip_to_human_readable_ip($address);
        my $ip_class = $ip =~ s/\.\d+$/\.0/r;    # A class C will always be in the same country
        $_country_code_name_cache{$ip_class} ||= [ $geo->LookUp($ip_class) ];
        push @results, {
            'ip'           => $ip,
            'country_code' => ( $_country_code_name_cache{$ip_class}->[0] || '' ),
            'country_name' => ( $_country_code_name_cache{$ip_class}->[1] || '' ),
            map { lc $_ => ( $ref->{$_} =~ tr/&<>"'// ? Cpanel::Encoder::Tiny::safe_html_encode_str( $ref->{$_} ) : $ref->{$_} ) } ( keys %{$ref} )
        };
    }

    return \@results;
}

sub flush_login_history {
    my $dbh = shift;

    my $delete_count;
    try {
        # numifying the result to handle cases where no rows are deleted, and dbh->do() returns '0e0'.
        $delete_count = 0 + $dbh->do('DELETE FROM login_track;');
    }
    catch {
        die Cpanel::Exception->create( "The “[_1]” table seems corrupted, and returned the following error: “[_2]”", [ 'cphulkd.login_track', Cpanel::Exception::get_string($_) ] );
    };
    return $delete_count;
}

sub flush_login_history_for_ip {
    my ( $dbh, $ip ) = @_;

    return unless $ip;

    my $delete_count;
    try {
        # numifying the result to handle cases where no rows are deleted, and dbh->do() returns '0e0'.
        $delete_count = 0 + $dbh->do( 'DELETE FROM login_track WHERE ADDRESS = ?', {}, Cpanel::IP::Convert::ip2bin16($ip) );
    }
    catch {
        die Cpanel::Exception->create( "The “[_1]” table seems corrupted, and returned the following error: “[_2]”", [ 'cphulkd.login_track', Cpanel::Exception::get_string($_) ] );
    };

    return $delete_count;
}

=head2 flush_bad_login_history_for_user($dbh, $user)

  $dbh   - A DBI Database Handle object
  $user  - The name of the user to flush bad logins for

Returns undef if no user was supplied. Returns the number of deleted bad logins if successful. Otherwise,
the function will throw an exception.

This function flushes any bad logins noted for a user. This is used during a password reset to remove
the bad logins for a user who tried too many incorrect passwords.

=cut

sub flush_bad_login_history_for_user {
    my ( $dbh, $user ) = @_;

    return unless $user;

    my $delete_count;
    try {
        # numifying the result to handle cases where no rows are deleted, and dbh->do() returns '0e0'.
        $delete_count = 0 + $dbh->do( 'DELETE FROM login_track WHERE USER = ? and TYPE < 0;', {}, $user );
    }
    catch {
        die Cpanel::Exception->create( "The “[_1]” table seems corrupted, and returned the following error: “[_2]”", [ 'cphulkd.login_track', Cpanel::Exception::get_string($_) ] );
    };

    return $delete_count;
}

=head2 clear_tempbans_for_user($dbh, $user)

  $dbh   - A DBI Database Handle object
  $user  - The name of the user to clear tempbans for

Always returns 1.

This function clears any temp XTables bans set for the user during a 'brute force' attempt.
This is used to clear any bans during a password reset on a user who accidentally locked
themselves out by entering too many different wrong passwords (the same password over and over will not ban).

=cut

sub clear_tempbans_for_user {
    my ( $dbh, $user ) = @_;

    return unless $user;

    my $user_brute_attempts = Cpanel::Hulk::Admin::get_user_brutes_for_user( $dbh, $user );
    return 1 if !@$user_brute_attempts;

    require Cpanel::XTables::TempBan;
    my $blocker = Cpanel::XTables::TempBan->new( 'chain' => 'cphulk' );

    my @errors;
    for my $brute_attempt (@$user_brute_attempts) {
        try {
            my $ipversion = Cpanel::Validate::IP::ip_version( $brute_attempt->{'ip'} );
            $blocker->ipversion($ipversion);
            $blocker->remove_temp_block( $brute_attempt->{'ip'} );
        }
        catch {
            push @errors, $_;
        };
    }

    if (@errors) {
        die Cpanel::Exception::create( 'Collection', [ exceptions => \@errors ] );
    }

    return 1;
}

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub _get_ip_range {
    my ($ip) = @_;

    my ( $start_address, $end_address ) = Cpanel::IP::Convert::ip_range_to_start_end_address($ip);

    if ( !length $start_address || !length $end_address ) {
        die Cpanel::Exception->create( "Invalid IP address or range: “[_1]”", [$ip] );
    }

    return ( $start_address, $end_address );
}

1;
