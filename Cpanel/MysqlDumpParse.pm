package Cpanel::MysqlDumpParse;

# cpanel - Cpanel/MysqlDumpParse.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This is an abstract class. Do not instantiate it directly.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Exception           ();
use Cpanel::MysqlUtils::Quote   ();
use Cpanel::MysqlUtils::Unquote ();

my $REGEXPS_ARE_INITIALIZED = 0;

#----------------------------------------------------------------------
# STATIC METHODS

#NOTE: This avoids a string copy.
sub looks_like {    ##no critic qw(RequireArgUnpacking)
                    # $_[0]: class
                    # $_[1]: statement
    my $class = $_[0];

    _init_regexps() if !$REGEXPS_ARE_INITIALIZED;

    return ( $_[1] =~ $class->REGEXP() );
}

#This should return the latest version that the parsing subclass knows
#how to deal with. Ideally, no subclass should need to override this,
#but that means that whoever updates one of the subclasses for a new version
#will need to check all of the other subclasses.
sub mysql_version { return '5.5.37' }

#----------------------------------------------------------------------
# DYNAMIC METHODS

#NOTE: This avoids a string copy.
sub new {    ##no critic qw(RequireArgUnpacking)
             # $_[0]: class
             # $_[1]: statement
    my $class = $_[0];

    _init_regexps() if !$REGEXPS_ARE_INITIALIZED;

    my $self = bless {}, $class;

    my $stmt_regexp = $self->REGEXP();

    my @all_attrs = ( $self->ATTR_ORDER(), 'body' );

    @{$self}{ map { "_$_" } @all_attrs } = ( $_[1] =~ m<\s*$stmt_regexp\s*(.*\S)\s*>s ) or do {
        $self->_throw_invalid_statement_error( $_[1] );
    };

    my %quoter = %{ $self->QUOTER() };
    while ( my ( $key, $quoter ) = each %quoter ) {
        $self->{"_$key"} = Cpanel::MysqlUtils::Unquote->can("un$quoter")->( $self->{"_$key"} );
    }

    $self->{'_body'} =~ s<\s*[*]/\z><>g;

    return $self;
}

sub get {
    my ( $self, $what ) = @_;
    return $self->{"_$what"};
}

sub get_quoted {
    my ( $self, $what ) = @_;

    return $self->_get_quoter($what)->( $self->{"_$what"} );
}

sub set {
    my ( $self, $what, $val ) = @_;
    return $self->{"_$what"} = $val;
}

sub _get_quoter_name {
    my ( $self, $what ) = @_;

    my $quoter = $self->QUOTER()->{$what} or do {
        die Cpanel::Exception::create( 'InvalidParameter', 'The parameter, [_1], is not quoted.', [$what] );
    };

    return $quoter;
}

sub _get_quoter {
    my ( $self, $what ) = @_;

    my $quoter_name = $self->_get_quoter_name($what);
    return Cpanel::MysqlUtils::Quote->can($quoter_name);
}

sub _get_unquoter {
    my ( $self, $what ) = @_;

    my $quoter_name = $self->_get_quoter_name($what);
    return Cpanel::MysqlUtils::Unquote->can("un$quoter_name");
}

sub _sql_obj_name {
    my ( $self, $key1, $key2 ) = @_;

    my $obj_sql = $self->get_quoted($key2);

    if ( defined $self->{"_$key1"} ) {
        substr( $obj_sql, 0, 0 ) = $self->get_quoted($key1) . '.';
    }

    return $obj_sql;
}

#Assumes that the subclass defines a "definer_name" and a "definer_host".
sub _definer_to_string {
    my ($self) = @_;

    return undef if !defined $self->get('definer_name');

    return 'DEFINER=' . $self->get_quoted('definer_name') . '@' . $self->get_quoted('definer_host');
}

#----------------------------------------------------------------------
# perlcc 5.6 chokes on pre-runtime qr<>.

my $definer_re_part;
my $cdtl_comment_start;
my $end_begin_comment_re;
my $end_begin_comment_or_space_re;
my $optional_definer_re;

sub _init_regexps {
    $REGEXPS_ARE_INITIALIZED = 1;

    $definer_re_part = qr{
        DEFINER \s* = \s*
        ($Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP|$Cpanel::MysqlUtils::Unquote::IDENTIFIER_REGEXP)
        \s* [@] \s*
        ($Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP|$Cpanel::MysqlUtils::Unquote::IDENTIFIER_REGEXP)
    }xsi;

    $cdtl_comment_start = '(?:/[*]!\d+\s+)';

    $end_begin_comment_re = qr{
        [*]/
        \s*
        $cdtl_comment_start
    }xs;

    $end_begin_comment_or_space_re = qr{
        (?: \s* $end_begin_comment_re \s* | \s+ )
    }xs;

    $optional_definer_re = qr{
        (?:
            $definer_re_part
            $end_begin_comment_or_space_re
        )?
    }xs;

    return;
}

#
# Returns a regular expresion good for finding and parsing out DEFINERs
# Public function - regexes may not have yet been initialized
#
sub get_definer_re {

    _init_regexps() if !$REGEXPS_ARE_INITIALIZED;

    return $definer_re_part;
}

#----------------------------------------------------------------------
# Expose what is necessary as private methods here.

sub _create_begin_re {
    return qr{
        \A
        \s*
        $cdtl_comment_start?
        \s*
        CREATE
        $end_begin_comment_or_space_re
    }xsi;
}

#Basically, CREATE plus optional DEFINER.
sub _create_begin_definer_re {
    my $_create_begin_re = _create_begin_re();
    return qr{
        $_create_begin_re
        $optional_definer_re
    }xsi;

}

sub _optional_definer_re {
    return $optional_definer_re;
}

#Optional DB name, then the DB object name.
sub _db_obj_re_part {
    return qr{
        (?:
            ($Cpanel::MysqlUtils::Unquote::IDENTIFIER_REGEXP)
            \s*
            [.]
        )?
        \s*
        ($Cpanel::MysqlUtils::Unquote::IDENTIFIER_REGEXP)
    }xs;
}

#----------------------------------------------------------------------

1;
