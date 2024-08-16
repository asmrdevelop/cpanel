package Cpanel::MysqlDumpParse::Trigger;

# cpanel - Cpanel/MysqlDumpParse/Trigger.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: Do NOT depend on this parser to accommodate conditional comments!
# It is absolutely critical to strip these out before calling this mdoule.
# See Cpanel::MysqlUtils::Statements::strip_comments_for_version().
#----------------------------------------------------------------------

use strict;

use Cpanel::Exception ();

use base qw(Cpanel::MysqlDumpParse);

my $trigger_re;

sub REGEXP {
    return $trigger_re ||= do {
        my $create_begin_definer_re = __PACKAGE__->_create_begin_definer_re();
        my $db_obj_re_part          = __PACKAGE__->_db_obj_re_part();

        qr<
            $create_begin_definer_re    #0/1: definer name/host
            TRIGGER
            \s+
            $db_obj_re_part             #2/3: trigger DB/name
            \s+
            (\S+)                       #4: trigger time
            \s+
            (\S+)                       #5: trigger event
            \s+
            ON
            \s+
            $db_obj_re_part             #6/7: table DB/name
            \s+
            FOR \s+ EACH \s+ ROW
        >xsi;
    };
}

sub ATTR_ORDER {
    return qw(
      definer_name
      definer_host
      trigger_db
      trigger_name
      time
      event
      table_db
      table_name
    );
}

sub QUOTER {
    return {
        qw<
          definer_name    quote_identifier
          definer_host    quote_identifier
          trigger_db      quote_identifier
          trigger_name    quote_identifier
          table_db        quote_identifier
          table_name      quote_identifier
        >
    };
}

sub _throw_invalid_statement_error {
    my ( $self, $mysqldump_stmt ) = @_;

    die Cpanel::Exception::create( 'InvalidParameter', 'The following is not a valid MySQL command to create a trigger: [_1]', [$mysqldump_stmt] );
}

sub to_string {
    my ($self) = @_;

    return join(
        q< >,
        (
            'CREATE',
            ( $self->_definer_to_string() || () ),
            'TRIGGER',
            $self->_sql_obj_name( 'trigger_db', 'trigger_name' ),
            $self->get('time'),
            $self->get('event'),
            'ON',
            $self->_sql_obj_name( 'table_db', 'table_name' ),
            'FOR EACH ROW',
            $self->get('body'),
        )
    );
}

1;
