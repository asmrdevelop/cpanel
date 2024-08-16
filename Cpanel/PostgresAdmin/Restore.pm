package Cpanel::PostgresAdmin::Restore;

# cpanel - Cpanel/PostgresAdmin/Restore.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#----------------------------------------------------------------------
#NOTE: These routines are NOT general-purpose parsers for their respective
#statements. They are meant specifically to parse the output of statements
#from Cpanel::PostgresAdmin as found in account backups.
#----------------------------------------------------------------------

use Cpanel::PostgresUtils                ();
use Cpanel::PostgresUtils::Quote         ();
use Cpanel::Validate::LineTerminatorFree ();

#Returns an array ref of [ [ granted, grantee ], .. ]
sub parse_grants_file_sr_from_postgresadmin {
    my ($contents_sr) = @_;

    return _parse_file_by_line( $contents_sr, \&_parse_role_grant_from_PostgresAdmin );
}

#Returns an array ref of [ [ username, pw ], .. ]
sub parse_users_file_sr_from_postgresadmin {
    my ($contents_sr) = @_;

    return _parse_file_by_line( $contents_sr, \&_parse_user_creation_from_PostgresAdmin );
}

#All PostgresAdmin knows how to create is this, so it's all we parse.
#
#Input: grant string, e.g., q{GRANT "person" TO "felipe"}
#   OR q{GRANT ALL ON DATABASE "thing" TO "felipe"}
#Output: (granted, grantor), e.g., qw(person felipe)
#
sub _parse_role_grant_from_PostgresAdmin {
    my ($str) = @_;

    my @matches = (
        $str =~ m{
        \A
        GRANT
        (?: \s+ ALL (?: \s+ PRIVILEGES )? \s+ ON \s+ DATABASE)?
        \s+
        ($Cpanel::PostgresUtils::IDENTIFIER_REGEXP)
        \s+
        TO
        \s+
        ($Cpanel::PostgresUtils::IDENTIFIER_REGEXP)
        \z
    }xi
    );

    return if !@matches;

    Cpanel::Validate::LineTerminatorFree::validate_or_die($_) for @matches;

    $_ = Cpanel::PostgresUtils::Quote::unquote_identifier($_) for @matches;

    #In case called in scalar context...
    return @matches[ 0, 1 ];
}

sub _parse_file_by_line {
    my ( $contents_sr, $line_parser_cr ) = @_;

    my @parses;
    while ( $$contents_sr =~ m{([^\r\n]*)(?:[\r\n]|\z)}g ) {
        next if !length $1;

        my $line = $1;

        $line =~ s{\A\s+|\s*;?\s*\z}{}g;

        my @parse;
        local $@;
        eval { @parse = $line_parser_cr->($line) };

        if (@parse) {
            push @parses, \@parse;
        }
    }

    return \@parses;
}

#All PostgresAdmin knows how to create is this, so it's all we parse.
#
#Input: CREATE USER string (e.g., q{CREATE USER "felipe" WITH PASSWORD 'foo')
#Output: (username, password), e.g., qw(felipe  foo)
#
#NOTE: This will reject if the password string isn't a PgSQL "escape" string.
#
sub _parse_user_creation_from_PostgresAdmin {
    my ($str) = @_;

    my ( $username, $password ) = (
        $str =~ m{
        \A
        CREATE \s+ USER
        \s+
        ($Cpanel::PostgresUtils::IDENTIFIER_REGEXP)
        \s+
        WITH \s+ PASSWORD
        \s+
        ([^\0]*)
    }xi
    );

    return if !length $username;

    $username = Cpanel::PostgresUtils::Quote::unquote_identifier($username);

    local $@;
    eval {
        $password = Cpanel::PostgresUtils::Quote::unquote_e($password);
        1;
    } or return;

    Cpanel::Validate::LineTerminatorFree::validate_or_die($_) for ( $username, $password );

    return ( $username, $password );
}

1;
