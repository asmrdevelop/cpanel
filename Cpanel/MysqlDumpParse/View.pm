package Cpanel::MysqlDumpParse::View;

# cpanel - Cpanel/MysqlDumpParse/View.pm           Copyright 2022 cPanel, L.L.C.
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
# It does NOT do a complete parse of a CREATE VIEW statement.
#----------------------------------------------------------------------

use strict;

use Cpanel::Exception ();

use base qw(Cpanel::MysqlDumpParse);

my $regexp;

sub REGEXP {
    return $regexp ||= do {
        my $create_begin_re     = __PACKAGE__->_create_begin_re();
        my $db_obj_re_part      = __PACKAGE__->_db_obj_re_part();
        my $optional_definer_re = __PACKAGE__->_optional_definer_re();

        qr<
            $create_begin_re
            (OR \s+ REPLACE \s+)?              #0: or_replace
            (?:ALGORITHM \s* = \s* (\S+) \s+)?   #1: algorithm
            $optional_definer_re            #2/3: definer name/host
            (?:SQL \s+ SECURITY \s+ (\S+) \s+)? #4: sql_security
            VIEW \s+
            $db_obj_re_part                     #5/6: view DB/name
        >xsi;
    };
}

sub ATTR_ORDER {
    return qw(
      or_replace
      algorithm
      definer_name
      definer_host
      sql_security
      view_db
      view_name
    );
}

sub QUOTER {
    return {
        qw<
          definer_name  quote_identifier
          definer_host  quote_identifier
          view_db       quote_identifier
          view_name     quote_identifier
        >
    };
}

sub _throw_invalid_statement_error {
    my ( $self, $mysqldump_stmt ) = @_;

    die Cpanel::Exception::create( 'InvalidParameter', 'The following is not a valid MySQL command to create a view: [_1]', [$mysqldump_stmt] );
}

sub to_string {
    my ($self) = @_;

    return join(
        q< >,
        (
            'CREATE',
            ( $self->get('or_replace') ? 'OR REPLACE'                           : () ),
            ( $self->get('algorithm')  ? 'ALGORITHM=' . $self->get('algorithm') : () ),
            ( $self->_definer_to_string() || () ),
            ( $self->get('sql_security') ? 'SQL SECURITY ' . $self->get('sql_security') : () ),
            'VIEW',
            $self->_sql_obj_name( 'view_db', 'view_name' ),
            $self->get('body'),
        )
    );
}

1;
