package Cpanel::MysqlDumpParse::Routine;

# cpanel - Cpanel/MysqlDumpParse/Routine.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: Do NOT depend on this parser to accommodate conditional comments!
# It is absolutely critical to strip these out before calling this mdoule.
# See Cpanel::MysqlUtils::Statements::strip_comments_for_version().
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# NOTE: This module is here to serve the needs of the account restore system.
# It does NOT do a complete parse of a CREATE PROCEDURE or CREATE FUNCTION
# statement; if such is ever needed, then replace this module with a module for
# CREATE PROCEDURE and another for CREATE FUNCTION.
#----------------------------------------------------------------------

use strict;

use Cpanel::Exception ();

use base qw(Cpanel::MysqlDumpParse);

my $procfunc_re;

sub REGEXP {
    return $procfunc_re ||= do {
        my $create_begin_definer_re = __PACKAGE__->_create_begin_definer_re();
        my $db_obj_re_part          = __PACKAGE__->_db_obj_re_part();

        qr<
            $create_begin_definer_re    #0/1: definer name/host
            (PROCEDURE|FUNCTION)        #2: what this is
            $db_obj_re_part             #3/4: procfunc DB/name
        >xsi;
    };
}

sub ATTR_ORDER {
    return qw(
      definer_name
      definer_host
      routine_type
      routine_db
      routine_name
    );
}

sub QUOTER {
    return {
        qw<
          definer_name    quote_identifier
          definer_host    quote_identifier
          routine_db      quote_identifier
          routine_name    quote_identifier
        >
    };
}

sub to_string {
    my ($self) = @_;

    return join(
        q< >,
        (
            'CREATE',
            ( $self->_definer_to_string() || () ),
            $self->get('routine_type'),
            $self->_sql_obj_name( 'routine_db', 'routine_name' ),
            $self->get('body'),
        )
    );
}

sub _throw_invalid_statement_error {
    my ( $self, $mysqldump_stmt ) = @_;

    die Cpanel::Exception::create( 'InvalidParameter', 'The following is not a valid MySQL command to create a procedure or function: [_1]', [$mysqldump_stmt] );
}

1;
