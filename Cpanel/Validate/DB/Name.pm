package Cpanel::Validate::DB::Name;

# cpanel - Cpanel/Validate/DB/Name.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DB::Reserved        ();
use Cpanel::Exception           ();
use Cpanel::Validate::DB::Utils ();

our $max_mysql_dbname_length = 64;
our $max_pgsql_dbname_length = 63;

my %reserved_database_names;
my @reserved_database_regexps;

my $locale;

sub verify_mysql_database_name {
    my ($database_name) = @_;

    verify_mysql_database_name_format($database_name);

    _verify_database_name_not_reserved($database_name);

    return 1;
}

sub verify_pgsql_database_name {
    my ($database_name) = @_;

    verify_pgsql_database_name_format($database_name);

    _verify_database_name_not_reserved($database_name);

    return 1;
}

#Doesn't check to see if the name is reserved.
sub verify_mysql_database_name_format {
    my ($database_name) = @_;

    _verify_database_name_but_not_length($database_name);

    my $err = Cpanel::Validate::DB::Utils::excess_statement( $database_name, $max_mysql_dbname_length );
    if ($err) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "$err " . Cpanel::Validate::DB::Utils::locale()->maketext( 'A database name cannot exceed [quant,_1,character,characters].', $max_mysql_dbname_length ) );
    }

    #remove if we ever work around the wildcards-count-as-two problem
    _verify_special_mysql_wildcards_in_dbnames_case($database_name);

    _verify_mysqldump_bug_limitation($database_name);

    if ( substr( $database_name, -1 ) eq ' ' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'A database name cannot end with a space character.' );
    }

    return 1;
}

#Doesn't check to see if the name is reserved.
sub verify_pgsql_database_name_format {
    my ($database_name) = @_;

    _verify_database_name_but_not_length($database_name);

    my $err = Cpanel::Validate::DB::Utils::excess_statement( $database_name, $max_pgsql_dbname_length );
    if ($err) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "$err " . Cpanel::Validate::DB::Utils::locale()->maketext( 'A PostgreSQL database name cannot exceed [quant,_1,character,characters].', $max_pgsql_dbname_length ) );
    }

    return 1;
}

sub reserved_database_check {
    _init();

    no warnings 'redefine';
    *reserved_database_check = \&_reserved_database_check;

    goto &_reserved_database_check;
}

#----------------------------------------------------------------------

sub _verify_mysqldump_bug_limitation {
    my ($name) = @_;

    #We can’t allow backslash because of a bug in mysqldump:
    #
    #   https://bugs.mysql.com/bug.php?id=78932
    #
    if ( $name =~ tr<\\><> ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is invalid because this system prohibits the backslash ([_2]) character in database names.', [ $name, '\\' ] );
    }

    return;
}

#exposed for testing
sub _get_mysql_version {
    require Cpanel::MysqlUtils::Version;
    return Cpanel::MysqlUtils::Version::current_mysql_version()->{'long'};
}

#remove if we ever work around the wildcards-count-as-two problem
sub _verify_special_mysql_wildcards_in_dbnames_case {
    my ($name) = @_;

    require Cpanel::MysqlUtils::Quote;
    my $escaped_length = length( Cpanel::MysqlUtils::Quote::escape_pattern($name) );
    my $excess         = $escaped_length - $max_mysql_dbname_length;

    if ( $excess > 0 ) {
        die Cpanel::Exception::create(
            'InvalidParameter', 'This database name has too many wildcard-sensitive characters ([list_and_quoted,_1]). The system stores each of these as two characters internally, up to a limit of [quant,_2,character,characters]. This name would take up [quant,_3,character,characters] of internal storage, which is [numf,_4] too many.',
            [ [ '\\', '_', '%' ], $max_mysql_dbname_length, $escaped_length, $excess ]
        );
    }

    return 1;
}

sub _verify_database_name_but_not_length {
    my ($database_name) = @_;

    if ( !length $database_name ) {
        die Cpanel::Exception::create( 'Empty', 'A database name cannot be empty.' );
    }

    #Space and tilde are the first and last printable ASCII characters.
    if ( $database_name =~ tr/ -~//c ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is invalid because this system allows only printable [asis,ASCII] characters in database names.', [$database_name] );
    }

    #This is just paranoia; there’s no actual documented breakage here.
    if ( $database_name =~ tr/'"`// ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is invalid because this system does not allow quote characters ([join,~, ,_2]) in database names.', [ $database_name, [qw(' " `)] ] );
    }

    #NOTE: We can’t allow slash because pkgacct stores database names
    #in filesystem node names.
    if ( $database_name =~ tr</><> ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is invalid because this system prohibits the slash ([_2]) character in database names.', [ $database_name, '/' ] );
    }

    return 1;
}

sub _verify_database_name_not_reserved {
    my ($database_name) = @_;

    if ( reserved_database_check($database_name) ) {
        die Cpanel::Exception::create( 'Reserved', '“[_1]” is a reserved name for databases on this system.', [$database_name], { value => $database_name } );
    }

    return 1;
}

sub _reserved_database_check {
    return 1 if exists $reserved_database_names{ $_[0] };

    for (@reserved_database_regexps) {
        return 1 if $_[0] =~ $_;
    }

    return 0;
}

my $_called_init;

sub _init {
    return if $_called_init;

    # If you change either of these values, you must change
    # Cpanel::Validate::Username::Core.
    @reserved_database_regexps = (
        qr<\Amydns>i,
        qr<\Apg_toast>,
        qr<\Apg_temp>,
    );

    %reserved_database_names = map { $_ => 1 } Cpanel::DB::Reserved::get_reserved_database_names();

    $_called_init = 1;

    return;
}

1;
