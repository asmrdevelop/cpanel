package Cpanel::MysqlDumpParse::Table;

# cpanel - Cpanel/MysqlDumpParse/Table.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: Do NOT depend on this parser to accommodate conditional comments!
# It is absolutely critical to strip these out before calling this module.
# See Cpanel::MysqlUtils::Statements::strip_comments_for_version().
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# NOTE: This module is here to serve the needs of the account restore system.
# It does NOT do a complete parse of a CREATE TABLE statement.
#----------------------------------------------------------------------

use strict;

use Cpanel::Exception ();

use base qw(Cpanel::MysqlDumpParse);

my $_re;

sub REGEXP {
    return $_re ||= do {
        my $db_obj_re_part = __PACKAGE__->_db_obj_re_part();

        qr<
            \A
            CREATE
            (?:
                \s+
                (TEMPORARY)?                #0: temporary
            )?
            \s+
            TABLE
            (?:
                \s+
                (IF \s+ NOT \s+ EXISTS)?    #1: if_not_exists
            )?
            \s+
            $db_obj_re_part             #2/3: table DB/name
        >xsi;
    };
}

sub ATTR_ORDER {
    return qw(
      temporary
      if_not_exists
      table_db
      table_name
    );
}

sub QUOTER {
    return {
        qw<
          table_db        quote_identifier
          table_name      quote_identifier
        >
    };
}

sub _throw_invalid_statement_error {
    my ( $self, $mysqldump_stmt ) = @_;

    die Cpanel::Exception::create( 'InvalidParameter', 'The following is not a valid MySQL command to create a table: [_1]', [$mysqldump_stmt] );
}

sub to_string {
    my ($self) = @_;

    return join(
        q< >,
        (
            'CREATE',
            ( $self->get('temporary') ? 'TEMPORARY' : () ),
            'TABLE',
            ( $self->get('if_not_exists') ? 'IF NOT EXISTS' : () ),
            $self->_sql_obj_name( 'table_db', 'table_name' ),
            $self->get('body'),
        )
    );
}

1;
