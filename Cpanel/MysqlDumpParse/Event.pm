package Cpanel::MysqlDumpParse::Event;

# cpanel - Cpanel/MysqlDumpParse/Event.pm          Copyright 2022 cPanel, L.L.C.
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
# It does NOT do a complete parse of a CREATE EVENT statement.
#----------------------------------------------------------------------

use strict;

use Cpanel::Exception ();

use base qw(Cpanel::MysqlDumpParse);

my $regexp;

sub REGEXP {
    return $regexp ||= do {
        my $create_begin_definer_re = __PACKAGE__->_create_begin_definer_re();
        my $db_obj_re_part          = __PACKAGE__->_db_obj_re_part();
        my $optional_definer_re     = __PACKAGE__->_optional_definer_re();

        qr<
            $create_begin_definer_re    #0/1: definer name/host
            \s* EVENT \s+
            (IF \s+ NOT \s+ EXISTS \s+)?              #2: if_not_exists
            $db_obj_re_part                     #3/4: event DB/name
        >xsi;
    };
}

sub ATTR_ORDER {
    return qw(
      definer_name
      definer_host
      if_not_exists
      event_db
      event_name
    );
}

sub QUOTER {
    return {
        qw<
          definer_name  quote_identifier
          definer_host  quote_identifier
          event_db      quote_identifier
          event_name    quote_identifier
        >
    };
}

sub _throw_invalid_statement_error {
    my ( $self, $mysqldump_stmt ) = @_;

    die Cpanel::Exception::create( 'InvalidParameter', 'The following is not a valid MySQL command to create an event: [_1]', [$mysqldump_stmt] );
}

sub to_string {
    my ($self) = @_;

    return join(
        q< >,
        (
            'CREATE',
            ( $self->_definer_to_string() || () ),
            'EVENT',
            ( $self->get('if_not_exists') ? 'IF NOT EXISTS' : () ),
            $self->_sql_obj_name( 'event_db', 'event_name' ),
            $self->get('body'),
        )
    );
}

1;
