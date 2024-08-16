package Cpanel::MysqlUtils::Grants;

# cpanel - Cpanel/MysqlUtils/Grants.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: Quoted parts of a GRANT have both quoted_$part and $part getter/setters.
# This is because MySQL allows wildcard characters in database names;
# e.g., granting privs on `*` affects only one db/table, whereas granting
# on * affects them all. To specify a grant on *, use the quoted_$part setter,
# e.g.,:
#   $grant->quoted_db_name('*');   #all dbs
# ...because if you do this:
#   $grant->db_name('*');           #only the `*` database
# ...you'll only be GRANTing onto a database named `*`!
#
# NOTE: db_name() and db_host() expect, and return, UNQUOTED, UNESCAPED input.
# Any wildcards passed in through them get escaped/quoted, and any that
# may have been set with quoted_db_name() or quoted_db_host() are
# indistinguishable from escaped characters when accessing.
# db_name() and db_host(), then, are NOT round-trip safe with
# unescaped wildcard characters.
# So don't try to round-trip wildcard '*', or $db_host =~ tr{%_}{},
# through this because those characters will be escaped/quoted
# (i.e., non-wildcards) in the eventual to_string() output.
#
# Sorry...
#----------------------------------------------------------------------
# TODO: MySQL supports more than one user_specification per GRANT statement.
# It would be useful to teach this module how to handle that; right
# now, though, it only knows how to do one user_specification per GRANT.
#
# HOWEVER, it does know how to spit out a version of the grant for arbitrarily
# many users. See to_string_for_users().
#----------------------------------------------------------------------

use cPstrict;

use Cpanel::MysqlUtils::Quote   ();
use Cpanel::MysqlUtils::Unquote ();
use Cpanel::MysqlUtils::Version ();
use Cpanel::LoadModule          ();
use Cpanel::Database            ();
use Try::Tiny;

our $mysql_version;

# XXX t/Whostmgr-Accounts-Create_invalid.t seems to do some crazy stuff.
# Allow setting mysql_version on import to avoid these shenanigans.
sub import {
    my ( $package, $ver ) = @_;
    $mysql_version = $ver if $ver;
    return;
}

our %ATTRIBUTE_QUOTERS = (
    db_name => [ \&Cpanel::MysqlUtils::Quote::quote_pattern_identifier, \&Cpanel::MysqlUtils::Unquote::unquote_pattern_identifier ],
    db_obj  => [ \&Cpanel::MysqlUtils::Quote::quote_identifier,         \&Cpanel::MysqlUtils::Unquote::unquote_identifier ],
    db_user => [ \&Cpanel::MysqlUtils::Quote::quote,                    \&Cpanel::MysqlUtils::Unquote::unquote ],
    db_host => [ \&Cpanel::MysqlUtils::Quote::quote_pattern,            \&Cpanel::MysqlUtils::Unquote::unquote_pattern ],
);

#Order is important!
my @ATTRIBUTES = qw(
  db_privs
  db_object_type
  db_name
  db_obj
  db_user
  db_host
  db_rest
);

my %RAW_ASTERISK_OK = map { $_ => undef } qw(
  db_name
  db_obj
);

my %_quote_cache;

#----------------------------------------------------------------------
#NOTE: Per JNK, it is necessary to write out these getters and setters
#and NOT create them dynamically, in order to reap compiler benefits.

sub _getter_setter {
    my ( $self, $attribute, $input ) = @_;

    my ( $quoter, $unquoter ) = $ATTRIBUTE_QUOTERS{$attribute} ? @{ $ATTRIBUTE_QUOTERS{$attribute} } : ();

    if ( @_ > 2 ) {
        if ($quoter) {
            $input = $quoter->($input);
        }

        $self->{"_$attribute"} = $input;
    }

    return $quoter ? $unquoter->( $self->{"_$attribute"} ) : $self->{"_$attribute"};
}

# TODO: It would be nice if db_privs() would accept/return a list, but that's
# complicated because an individual privilege can contain a quoted comma.
sub db_privs {
    return $_[0]->_getter_setter( 'db_privs', @_[ 1 .. $#_ ] );
}

#NOTE: NOT for use with wildcards! See note above.
sub db_name {
    return $_[0]->_getter_setter( 'db_name', @_[ 1 .. $#_ ] );
}

sub db_object_type {
    return $_[0]->_getter_setter( 'db_object_type', @_[ 1 .. $#_ ] );
}

sub db_obj {
    return $_[0]->_getter_setter( 'db_obj', @_[ 1 .. $#_ ] );
}

sub db_user {
    return $_[0]->_getter_setter( 'db_user', @_[ 1 .. $#_ ] );
}

#NOTE: NOT for use with wildcards! See note above.
sub db_host {
    return $_[0]->_getter_setter( 'db_host', @_[ 1 .. $#_ ] );
}

sub db_rest {
    return $_[0]->_getter_setter( 'db_rest', @_[ 1 .. $#_ ] );
}

sub _quoted_getter_setter {

    #my ( $self, $attribute, $input ) = @_;
    if ( @_ > 2 ) {

        $ATTRIBUTE_QUOTERS{ $_[1] }->[0] or die "“$_[1] is not quoted!";
        $_[0]->{"_$_[1]"} = $_[2];
    }
    return $_[0]->{"_$_[1]"};
}

sub quoted_db_name {
    return $_[0]->_quoted_getter_setter( 'db_name', @_[ 1 .. $#_ ] );
}

# db_obj is a MySQL object_type of: TABLE, FUNCTION, and/or PROCEDURE
sub quoted_db_obj {
    return $_[0]->_quoted_getter_setter( 'db_obj', @_[ 1 .. $#_ ] );
}

sub quoted_db_user {
    return $_[0]->_quoted_getter_setter( 'db_user', @_[ 1 .. $#_ ] );
}

sub quoted_db_host {
    return $_[0]->_quoted_getter_setter( 'db_host', @_[ 1 .. $#_ ] );
}

sub override_mysql_version {
    return $_[0]->_quoted_getter_setter( 'override_mysql_version', @_[ 1 .. $#_ ] );
}

#END Ugly written-out getters and setters
#----------------------------------------------------------------------

sub new ( $class, $grant = undef, $mysql_ver = undef ) {
    my $self = {};
    bless $self, $class;

    $self->override_mysql_version($mysql_ver) if $mysql_ver;
    $self->_init($grant);    # will return after setting version if $grant not defined

    return bless $self, $class;
}

# Instantiates a Cpanel::MysqlUtils::Grants object
# Handles exceptions and returns undef if failure
sub parse ($grant) {

    my $grant_object;

    try {
        $grant_object = Cpanel::MysqlUtils::Grants->new($grant);
    }
    catch {
        warn $_;
    };

    return $grant_object;
}

# Discards any lines that don't have GRANT in them, returns the first match.
sub _get_grant_line_from_input ($line) {
    my @lines = split( /\n/, $line );

    # No more than one line, why bother
    return $line unless scalar(@lines) > 1;
    @lines = grep { index( $_, 'GRANT' ) == 0; } @lines;

    # You'll probably die later if you return here
    return $line if !@lines;

    # Found it
    return $lines[0];
}

sub _init ( $self, $grant = undef ) {
    if ( !$mysql_version ) {
        require Cpanel::MysqlUtils::Version;
        $mysql_version = Cpanel::MysqlUtils::Version::mysqlversion();
    }

    return $self if !$grant;

    # Grants fed in here should be just one line. The object can't comprehend
    # anything other than that. If it is, we need to discard anything that is
    # not a GRANT statement. Since to_string will sometimes produce this
    # (ex. on mysql8), then we need to tolerate it internally.
    my $orig_grant = $grant;
    $grant = _get_grant_line_from_input($grant);
    $grant =~ s{;\s*\z}{};

    my $object_type   = '(?: ( PROCEDURE | FUNCTION | TABLE ) \s+ )?';
    my $quoted_regexp = "($Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP|$Cpanel::MysqlUtils::Unquote::IDENTIFIER_REGEXP)";

    my @parts = $grant =~ m/
                \A\s*                                       #
                GRANT\s+                                    #
                ([^\r\n'"]+?)                               # Privileges (can contain backtick-quoted identifiers)
                \s+ON\s+                                    #
                $object_type                                # Object type
                (\*|$Cpanel::MysqlUtils::Unquote::IDENTIFIER_REGEXP) # Database name
                \.                                          #
                (\*|$Cpanel::MysqlUtils::Unquote::IDENTIFIER_REGEXP) # Database object
                \s+TO\s+                                    #
                $quoted_regexp                              # Database user
                \@                                          #
                $quoted_regexp                              # Database host
                (                                           # The rest of the line (can contain quoted strings)
                    (?:\s+.*)?                              #
                )                                           #
                \s*\z                                       #
             /xmosi;

    if ( !@parts ) {
        die "Invalid grant string: $orig_grant\n";
    }

    @{$self}{ map { "_$_" } @ATTRIBUTES } = @parts;

    if ( $self->{'_db_rest'} =~ tr/ \t\r\n\f// ) {

        #Replace the single quotes so that the logic below won't interpret these
        #strings as unquoted.
        $self->{'_db_rest'} =~ s{\A\s+}{};
        $self->{'_db_rest'} =~ s{\s+\z}{};
    }

    # Override what's passed in, as if they passed it in but it looks like
    # it's from another version, then that's still just not appropriate for
    # our grant parse. Appropriate for output maybe, but not parsing.
    if ( Cpanel::MysqlUtils::Unquote::unquote( $self->{'_db_user'} ) eq $self->{'_db_user'} ) {

        # Transform them into being 5.7 looking grants.
        $self->{'_db_user'} = Cpanel::MysqlUtils::Quote::quote( Cpanel::MysqlUtils::Unquote::unquote_identifier( $self->{'_db_user'} ) );
        $self->{'_db_host'} = Cpanel::MysqlUtils::Quote::quote_pattern( Cpanel::MysqlUtils::Unquote::unquote_pattern_identifier( $self->{'_db_host'} ) );
    }

    while ( my ( $attr, $quoter_code_ar ) = each %ATTRIBUTE_QUOTERS ) {
        my $raw = $self->{"_$attr"};
        my ( $quoter, $unquoter ) = @{$quoter_code_ar};

        if ( $raw eq '*' ) {
            next if exists $RAW_ASTERISK_OK{$attr};

            die "“$attr” may not be unquoted “*”: $orig_grant\n";
        }

        #If what we got from the parse is not quoted, then quote
        #and store the quoted value.
        my $roundtrip_quoted = $_quote_cache{$attr}{$raw} ||= $quoter->( $unquoter->($raw) );
        if ( substr( $raw, 0, 1 ) ne substr( $roundtrip_quoted, 0, 1 ) ) {
            $self->can("quoted_$attr")->( $self, $roundtrip_quoted );
        }
    }

    if (
           $self->quoted_db_name() eq '*'
        && $self->quoted_db_obj() ne '*'    # db_obj is a MySQL object_type of: TABLE, FUNCTION, and/or PROCEDURE

    ) {
        die "“db_name” may not be unquoted “*” unless “db_obj” is also unquoted “*”: $orig_grant\n";
    }

    local $@;
    foreach my $attr (@ATTRIBUTES) {
        next if !length $self->{"_$attr"};
        if ( $self->{"_$attr"} =~ tr/\r\n\f// ) {

            # For MySQL version 8.0, the db_rest attribute may have line breaks in it
            # if the caching_sha2_password authentication plugin is used
            if ( $attr ne 'db_rest'
                || !Cpanel::MysqlUtils::Version::is_at_least_version_and_of_vendor( $mysql_version, '8.0', 'mysql' ) ) {
                die "_$attr may not contain new lines: $orig_grant\n";
            }
        }
    }
    return $self;
}

# For MySQL 8, you'll often want to get this and create the user before trying to apply GRANTs
sub create_user_string ($self) {
    return '' if $self->db_rest() && $self->db_rest() !~ m/IDENTIFIED/;
    my $has_wildcard = $self->db_host() eq '%';
    my $db_host      = $has_wildcard ? q<'%'> : $self->quoted_db_host();
    my $str          = "CREATE USER IF NOT EXISTS " . $self->quoted_db_user() . '@' . $db_host;
    $str .= " " . $self->db_rest_to_sanity() if length $self->db_rest();
    $str .= ";";
    return $str;
}

sub db_rest_to_sanity ($self) {
    my $has_pw = 0;
    my $pw_str = '';

    # Don't foreverloop by trying to execute to_string in there.
    # Just don't die instead.
    $pw_str = $self->password(1);
    if ($pw_str) {
        $has_pw = 1;
    }
    else {
        $pw_str = $self->hashed_password(1);
    }
    my $ver = $self->override_mysql_version() || $mysql_version || Cpanel::MysqlUtils::Version::mysqlversion();
    my $str = ' IDENTIFIED ';
    if ( !$has_pw ) {
        if ( Cpanel::MysqlUtils::Version::is_at_least_version_and_of_vendor( $ver, '8.0', 'mysql' ) ) {

            # Yeah, yeah. I know. Real efficient to unquote then requote, right?
            $str .= "WITH 'mysql_native_password' AS " . Cpanel::MysqlUtils::Quote::quote($pw_str);
        }
        else {
            $str .= "BY PASSWORD(" . Cpanel::MysqlUtils::Quote::quote($pw_str) . ")";
        }

    }
    else {
        $str .= "BY " . Cpanel::MysqlUtils::Quote::quote($pw_str);
    }

    return $str;
}

# If you call to_string for MySQL 8, you almost certainly need to call create_user_string above or it will not work, as it needs the users to exist first
sub to_string_with_sanity {
    return _to_string_with_callback( $_[0], $_[1], \&db_rest_to_sanity );
}

sub to_string {
    return _to_string_with_callback( $_[0], $_[1], \&db_rest );
}

sub _to_string_with_callback {
    my ( $self, $no_add_db_rest, $cb ) = @_;
    my $str;

    # For MySQL 8, don't add the db_rest which includes the IDENTIFIED_BY stuff, which is a syntax error in 8
    my $ver          = $self->override_mysql_version() || $mysql_version || Cpanel::MysqlUtils::Version::mysqlversion();
    my $has_wildcard = $self->db_host() eq '%';
    my $db_host      = $has_wildcard ? q<'%'> : $self->quoted_db_host();
    if ( Cpanel::MysqlUtils::Version::is_at_least_version_and_of_vendor( $ver, '8.0', 'mysql' ) ) {
        $str = $self->create_user_string() . "\n";
        $str .= $self->_to_string_before_user() . $self->quoted_db_user() . '@' . $db_host . ';';
    }
    else {
        # Just construct the rest yourself to avoid issues with db_rest :)
        $str = $self->_to_string_before_user() . $self->quoted_db_user() . '@' . $db_host;
        if ( !$no_add_db_rest && length $self->db_rest() ) {
            $str .= q{ } . $cb->($self);
        }
        $str .= ';';
    }
    return $str;
}

sub db_name_pattern ($self) {
    return Cpanel::MysqlUtils::Unquote::unquote_identifier( $self->quoted_db_name() );
}

sub db_name_has_wildcard ($self) {
    return 1 if $self->quoted_db_name() eq '*';
    return 1 if $self->quoted_db_name() =~ m{(?<!\\)[_%]};

    return 0;
}

sub matches_db_name ( $self, $db ) {
    return 1 if $self->quoted_db_name() eq '*';

    my $mysql_pattern = $self->db_name_pattern();

    return like( $db, $mysql_pattern );
}

sub db_host_pattern ($self) {
    return Cpanel::MysqlUtils::Unquote::unquote( $self->quoted_db_host() );
}

sub db_host_has_wildcard ($self) {
    return 1 if $self->quoted_db_host() =~ m{(?<!\\)[_%]};

    return 0;
}

sub matches_db_host ( $self, $db ) {
    return 1 if $self->quoted_db_host() eq '*';

    my $mysql_pattern = $self->db_host_pattern();

    return like( $db, $mysql_pattern );
}

sub password ( $self, $no_die = undef ) {
    my ($quoted) = $self->db_rest() =~ m<IDENTIFIED\s+BY\s+(\S+)>i;

    if ( !$quoted || $quoted =~ m<\APASSWORD\s*|IDENTIFIED\s+WITH\s+\S+\s+AS\s+\S+>i ) {
        return if $no_die;
        my $string = $self->to_string();
        die "The grant “$string” does not contain an unhashed password.";
    }

    return Cpanel::MysqlUtils::Unquote::unquote($1);
}

sub hashed_password ( $self, $no_die = undef ) {

    # Recall that capture groups will still be like $1, $2, $3, $4 here even with the pipe operator
    my @matched_groups = $self->db_rest() =~ m<IDENTIFIED\s+BY\s+(PASSWORD)\s+(\S+)|IDENTIFIED\s+WITH\s+(\S+)\s+AS\s+(\S+)>i;
    my ( $quoted_method, $quoted_pwhash ) = $matched_groups[1] ? ( @matched_groups[ 0, 1 ] ) : ( @matched_groups[ 2, 3 ] );

    my $raw_pass_hash = Cpanel::MysqlUtils::Grants::unhex_hash( Cpanel::MysqlUtils::Unquote::unquote($quoted_pwhash) );
    if ( !$no_die && !$raw_pass_hash ) {
        my $string = $self->to_string();
        die "The grant “$string” does not contain a hashed password.";
    }
    if ($quoted_method) {
        $self->{'_db_authentication_plugin'} = Cpanel::MysqlUtils::Unquote::unquote($quoted_method);
    }

    return $raw_pass_hash;
}

#This special function returns a version of the grant that replaces the
#user/host section with one OR MORE user/host/password groups.
#Note that this class currently CANNOT parse the output of this method!
#
#Each member of @users_ar is a hashref of: {
#   user
#   host (wildcard permitted)
#   password OR hashed_password (optional)
#}
sub to_string_for_users ( $self, @users_ar ) {
    my @user_strs;
    for my $user_hr (@users_ar) {
        my $str = Cpanel::MysqlUtils::Quote::quote( $user_hr->{'user'} ) . '@' . Cpanel::MysqlUtils::Quote::quote( $user_hr->{'host'} );
        push @user_strs, $str;
    }

    return $self->_to_string_before_user() . join( ',', @user_strs ) . ';';
}

# See above sub. @users_ar is same one. This used to create/alter users
# and set passwords.
# We code for maximum compatibility and use CREATE/ALTER statements for
# password set now, as GRANT no longer allows this on MySQL 8.
sub to_string_for_users_manage ( $self, $action_keyword, @users_ar ) {
    my @user_statements;

    my $db = Cpanel::Database->new();

    for my $user_hr (@users_ar) {

        my %args = ();

        $args{name} = Cpanel::MysqlUtils::Quote::quote( $user_hr->{'user'} ) . '@' . Cpanel::MysqlUtils::Quote::quote( $user_hr->{'host'} );

        # Call function to get plugin type from hash
        my $auth_plugin = identify_hash_plugin( $user_hr->{'hashed_password'}, 1 );
        $user_hr->{'auth_plugin'} ||= $auth_plugin || 'mysql_native_password';
        $args{plugin} = Cpanel::MysqlUtils::Quote::quote( $user_hr->{'auth_plugin'} );

        $args{hashed} = $user_hr->{'hashed_password'} && $user_hr->{'hashed_password'} ne 'NULL';
        $args{pass}   = $args{hashed} ? Cpanel::MysqlUtils::Quote::quote( $user_hr->{'hashed_password'} ) : Cpanel::MysqlUtils::Quote::quote( $user_hr->{'password'} );

        $args{exists} = $action_keyword =~ /alter/i ? 1 : 0;

        push @user_statements, $db->get_set_password_sql(%args);
    }
    return join( "\n", @user_statements ) . "\n";
}

#----------------------------------------------------------------------

sub _to_string_before_user ($self) {
    my $str = sprintf 'GRANT %s ON%s %s.%s TO ', (
        $self->db_privs(),
        $self->db_object_type() ? ' ' . $self->db_object_type() : '',
        $self->quoted_db_name(),
        $self->quoted_db_obj(),    # db_obj is a MySQL object_type of: TABLE, FUNCTION, and/or PROCEDURE
    );
    return $str;
}

sub like ( $operand, $pattern ) {
    tr{A-Z}{a-z} for ( $operand, $pattern );

    my %string_escape_chars = (
        ( reverse %Cpanel::MysqlUtils::Quote::QUOTE_ESCAPE_CHARACTER ),
        ( map { $_ => $_ } @Cpanel::MysqlUtils::Quote::PATTERN_ESCAPE_CHARACTERS ),
    );

    my $regexp;
    while ( length $pattern ) {
        my $char = substr( $pattern, 0, 1, q{} );
        if ( $char eq q{\\} ) {
            my $escaped_char = substr( $pattern, 0, 1, q{} );
            if ( length $escaped_char ) {
                $regexp .= quotemeta( $string_escape_chars{$escaped_char} || $escaped_char );
            }
            else {
                $regexp .= quotemeta $char;
            }
        }
        elsif ( $char eq '_' ) {
            $regexp .= '.';
        }
        elsif ( $char eq '%' ) {
            $regexp .= '.*';
        }
        else {
            $regexp .= quotemeta $char;
        }
    }

    return ( $operand =~ m/^$regexp$/ ) ? 1 : 0;
}

###########################################################################
#
# Method:
#   show_grants_for_user
#
# Description:
#   This function gets all the grants for a specified MySQL user on all hosts.
#   Note that a nonexistent username is not considered an error condition.
#
# Parameters:
#   $dbh   - A database handle with an active MySQL connection.
#   $user  - The MySQL username whose grants will be shown.
#
# Exceptions:
#   die - Thrown if the database query fails.
#
# Returns:
#   This function returns an arrayref of L<Cpanel::MysqlUtils::Grants>
#   instances: one for each of the user’s grants. (The array will be empty
#   if a nonexistent MySQL username was passed in.)
#
sub show_grants_for_user ( $dbh, $user ) {
    local $dbh->{'RaiseError'} = 1;

    my @grants;

    my $hosts_ar = $dbh->selectall_arrayref( 'SELECT host FROM ' . DB_MYSQL() . '.user WHERE user = ?', undef, $user );

    #Use this construct to avoid the try/catch overhead for each user@host.
    while (@$hosts_ar) {
        try {
            while ( my $host = ( shift @$hosts_ar || [] )->[0] ) {

                # The 'next' here is a valid use case, and
                # the perlcritic policy triggers incorrectly
                my @grant_txts = $dbh->show_grants( $user, $host ) or next;
                ## use critic
                for my $grant_txt (@grant_txts) {
                    my $grant_obj = Cpanel::MysqlUtils::Grants::parse($grant_txt) or next;
                    push @grants, $grant_obj;
                }
            }
        }
        catch {
            Cpanel::LoadModule::load_perl_module('Cpanel::Mysql::Error');

            #ER_NONEXISTING_GRANT happens if the grant that we read is was
            #for a user that doesn't actually exist. In this case, we don't
            #care about the error and just want to keep going.
            my $error = $dbh->err() || $_;
            die $_ if $error ne Cpanel::Mysql::Error::ER_NONEXISTING_GRANT();
        }
    }

    return \@grants;
}

sub DB_MYSQL { return 'mysql' }

sub identify_hash_plugin ( $hash = undef, $unhex = undef ) {
    return '' if !$hash;
    $hash =~ s/^0x//;

    # If we have a hex string and $unhex == 1, unhex it and find the unencoded plugin type
    if ( defined($unhex) && $unhex == 1 ) {
        $hash = unhex_hash($hash);
    }
    if ( $hash =~ m/^\$A\$\d+\$/ ) {
        return 'caching_sha2_password';
    }
    elsif ( $hash =~ m/^\$\d+\$/ ) {
        return 'sha256_password';
    }
    elsif ( $hash =~ m/^\*.+/ ) {
        return 'mysql_native_password';
    }
    elsif ( $hash !~ tr/0-9A-Fa-f//c ) {
        return 'hex';
    }
    else {
        return '';
    }
}

# doing the length/proper chars check here rather than require caller to verify it, returns what it got if isn't hex
sub unhex_hash ( $hex = undef ) {
    return if !$hex;
    return $hex if $hex !~ m/^0x/;    # don't try to unhex a mysql_native_password hash or non-hexes
    $hex =~ s/^0x//;
    if ( length $hex && $hex !~ tr/0-9A-Fa-f//c ) {
        return pack( "H*", $hex );
    }
    else {
        return $hex;
    }
}

1;
