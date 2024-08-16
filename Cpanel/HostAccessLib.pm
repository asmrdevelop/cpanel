package Cpanel::HostAccessLib;

# cpanel - Cpanel/HostAccessLib.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Carp             ();
use Cpanel::SafeFile ();
use Cpanel::Debug    ();

our $VERSION = '0.8';

our $HOSTS_ALLOW = '/etc/hosts.allow';
our $HOSTS_DENY  = '/etc/hosts.deny';

=head1 NAME

Cpanel::HostAccessLib

=head1 SYNOPSIS

  my $hostaccess_obj = Cpanel::HostAccessLib->new();
  $hostaccess_obj->add(
      ...
  );
  $hostaccess_obj->reserialize();
  $hostaccess_obj->commit();

=head1 DESCRIPTION

This module allows you to read and manipulate the host access files. For simplicity,
it uses /etc/hosts.allow for everything and empties out /etc/hosts.deny.

=head1 CONSTRUCTION

There are no constructor parameters.

=head1 UNDOCUMENTED

The following methods are undocumented. Most of them should not need to be called directly,
as they are mainly for internal implementation purposes.

  init
  fetch_actions
  fetch_wildcards
  fetch_operators
  fetch_expansions
  fetch_services
  parse_db
  ptrim
  action_deparse
  client_deparse
  daemon_deparse
  action_parse
  daemon_parse
  client_parse
  parse_host_access_line

=head1 METHODS

=cut

my %SERVICES = (
    'cpaneld'    => 'cPanel Service Daemon',
    'webmaild'   => 'WebMail Service Daemon',
    'whostmgrd'  => 'Web Host Manager Service Daemon',
    'pop3'       => 'Pop3 Service Daemon',
    'imap'       => 'Imap Service Daemon',
    'smtp'       => 'SMTP Service Daemon',
    'cpdavd'     => 'WebDav/WebDisk Service Daemon',
    'mysql'      => 'MySQL Server',
    'snmp'       => 'SNMP Service',
    'auth'       => 'Ident Service',
    'domain'     => 'DNS Services',
    'ftp'        => 'Ftp Server',
    'sshd'       => 'SSH Service',
    'telnet'     => 'Telnet Service',
    'postgresql' => 'PostgreSQL Service',
    'ALL'        => 'All Services'
);
my @WILDCARDS = ( 'ALL', 'LOCAL', 'UNKNOWN', 'KNOWN', 'PARANOID' );
my @OPERATORS = ('EXCEPT');
my %ACTIONS   = (
    'banners' => '(/some/directory) Look  for  a  file  in  "/some/directory"  with  the  same  name  as  the  daemon  process  (for  example in.telnetd for the telnet service), and copy its contents to the client. Newline characters are replaced by carriage-return newline, and %<letter> sequences are expanded (see the hosts_access(5) manual page).',
    'nice'    => '[number] Change the nice value of the process (default 10).  Specify a positive value to spend more CPU resources on other processes.',
    'setenv'  => '(name) (value) Place a (name, value) pair into the process environment. The value is subjected to %<letter> expansions and may contain whitespace (but leading and trailing blanks are stripped off).',
    'umask'   => '(umask) Like the umask command that is built into the shell. Should be octal',
    'user'    => '(user[.group]) Ammume the privleges of the user and group',
    'rfc931'  =>
      '[timeout_in_seconds] Look up the client user name with the RFC 931 (TAP, IDENT, RFC 1413) protocol.  This option is silently ignored in case of services based on transports other than TCP.  It requires that the client system runs an RFC 931 (IDENT, etc.) -compliant daemon, and may cause noticeable delays with connections from non-UNIX clients.  The timeout period is optional. If no timeout is specified a compile-time defined default value is taken.',
    'linger'    => '(number_of_seconds) Specifies how long the kernel will try to deliver not-yet delivered data after the server process closes a connection.',
    'keepalive' => 'Causes the server to periodically send a message to the client.  The connection is considered broken when the client does not respond. The keepalive option can be useful when users turn off their machine while it is still connected to a server.  The keepalive option is not useful for datagram (UDP) services.',
    'spawn'     => '(shell_command) Execute,  in  a  child process, the specified shell command, after performing the %<letter> expansions described in the hosts_access(5) manual page.  The command is executed with stdin, stdout and stderr connected to the null device, so that it will not mess up the conversation with the client host.',
    'twist'     => '(shell_command) Replace the current process by an instance of the specified shell command, after performing the %<letter> expansions described in the hosts_access(5) manual page.',
    'severity'  => '(syslog level) Change the severity level at which the event will be logged. Facility names (such as mail) are optional, and are not supported on systems with older syslog implementations. The severity option can be used to emphasize or to ignore specific events.',
    'allow'     => 'Permits Service/Access',
    'deny'      => 'Denys Service/Access'
);
my %EXPANSIONS = (
    '%a' => 'The client (server) host address.',
    '%c' => 'Client information: user@host, user@address, a host name, or just an address, depending on how much information is available.',
    '%d' => 'The daemon process name (argv[0] value).',
    '%h' => 'The client (server) host name or address, if the host name is unavailable.',
    '%n' => 'The client (server) host name (or "unknown" or "paranoid").',
    '%p' => 'The daemon process id.',
    '%s' => 'Server information: daemon@host, daemon@address, or just a daemon name, depending on how much information is available.',
    '%u' => 'The client user name (or "unknown").',
    '%%' => 'Expands to a single "%" character.'
);

sub new {
    my ( $class, @args ) = @_;
    my $self = {};
    bless( $self, $class || 'Cpanel::HostAccessLib' );
    $self->init(@args);
    return $self;
}

sub init {
    my $self = shift;
    $self->{'DB'} = [];
    $self->parse_db( $HOSTS_ALLOW, 'ALLOW' );
    $self->parse_db( $HOSTS_DENY,  'DENY' );
    return;
}

sub fetch_actions {
    return \%ACTIONS;
}

sub fetch_wildcards {
    return \@WILDCARDS;
}

sub fetch_operators {
    return \@OPERATORS;
}

sub fetch_expansions {
    return \%EXPANSIONS;
}

sub fetch_services {
    return \%SERVICES;
}

sub parse_db {
    my $self           = shift;
    my $dbfile         = shift;
    my $default_action = shift;
    my $append_next_comment;
    my $dbl = Cpanel::SafeFile::safeopen( \*DBL, '<', $dbfile );
    if ( !$dbl ) {
        Cpanel::Debug::log_warn("Could not read from $dbfile");
        return;
    }
    my $buffer;
    while (<DBL>) {
        if (/\\[\r\n]*$/) {
            s/\\[\r\n]*$//g;
            $buffer .= $_;
            next;
        }

        $buffer .= $_;
        chomp $buffer;

        if ( $buffer =~ m/^\s*\#/ || $buffer =~ m/^$/ ) {
            if ($append_next_comment) {
                $append_next_comment = 0;
                my $count = @{ $self->{'DB'} } - 1;
                $buffer =~ s/^#//;
                @{ $self->{'DB'} }[$count]->{'comment'} = $buffer;
            }
            else {
                push(
                    @{ $self->{'DB'} },
                    {
                        'type'     => 'comment',
                        'contents' => $buffer,
                    }
                );
            }
        }
        else {
            my ( $ctl, $comment ) = split( /\#/, $buffer, 2 );
            my ( $daemon_list, $client_list, @actions ) = parse_host_access_line($ctl);
            push(
                @{ $self->{'DB'} },
                {
                    'daemon_list' => daemon_parse($daemon_list),
                    'client_list' => client_parse($client_list),
                    'action_list' => action_parse( \@actions, $default_action ),
                    'contents'    => $buffer,
                    'comment'     => $comment,
                    'type'        => 'access_list'
                }
            );
            $append_next_comment = 1 if !$comment;
        }
        $buffer = '';
    }
    return Cpanel::SafeFile::safeclose( \*DBL, $dbl );
}

=head2 reserialize()

Update the object's internal representation of the hosts_access data to include the latest ready-to-store
version of each entry in addition to the parsed version. In general, you should always call reserialize()
before calling commit(), or you will end up storing out-of-date or incomplete information.

This method does not accept any arguments.

=cut

sub reserialize {
    my $self = shift;
    for ( my $linenum = 0; $linenum <= $#{ $self->{'DB'} }; $linenum++ ) {
        if ( ${ $self->{'DB'} }[$linenum]->{'type'} ne 'comment' ) {
            ${ $self->{'DB'} }[$linenum]->{'contents'} = join( ' : ', daemon_deparse( ${ $self->{'DB'} }[$linenum]->{'daemon_list'} ), client_deparse( ${ $self->{'DB'} }[$linenum]->{'client_list'} ), action_deparse( ${ $self->{'DB'} }[$linenum]->{'action_list'} ), );
            if ( defined ${ $self->{'DB'} }[$linenum]->{'comment'} && ${ $self->{'DB'} }[$linenum]->{'comment'} ne '' ) {

                # do not write end of line comments -- fix bug 5607
                ${ $self->{'DB'} }[$linenum]->{'contents'} .= "\n" . '#' . ${ $self->{'DB'} }[$linenum]->{'comment'};
            }
        }
    }
}

sub ptrim {
    my $strr = shift;
    $strr =~ s/^\s*|\s*$//g;
    return $strr;
}

sub action_deparse {
    my $aref = shift;
    if ( $#{$aref} == -1 ) {
        return 'allow';
    }
    return join( ' : ', @{$aref} );
}

sub client_deparse {
    my $cref = shift;
    return join( ' , ', @{$cref} );
}

sub daemon_deparse {
    my $dref = shift;

    return join( ' , ', @{$dref} );
}

sub action_parse {
    my $action         = shift;
    my $default_action = lc(shift);
    if ( $action eq '' ) { return $default_action }
    if ( ref $action eq 'ARRAY' ) {
        return [$default_action] if !@$action;
        return $action;
    }
    $action = ptrim($action);
    my @ACTIONS = split( /\s*:\s*/, $action );
    return \@ACTIONS;
}

sub daemon_parse {
    my $daemon_list = shift;
    my @DAEMONS     = split( /\s*\,\s*/, ptrim($daemon_list) );
    return \@DAEMONS;
}

sub client_parse {
    my $client_list = shift;
    my @CLIENTS     = split( /\s*\,\s*/, ptrim($client_list) );
    return \@CLIENTS;
}

=head2 commit()

Write the updated host access data to /etc/hosts.allow.

Note: You should call reserialize() before calling commit().

This method does not accept any arguments.

=cut

sub commit {
    my $self = shift;

    my $dbl = Cpanel::SafeFile::safeopen( \*DBL, '>', $HOSTS_ALLOW );
    if ( !$dbl ) {
        Cpanel::Debug::log_warn("Could not write to $HOSTS_ALLOW");
        return;
    }
    for ( my $linenum = 0; $linenum <= $#{ $self->{'DB'} }; $linenum++ ) {
        if (
            ${ $self->{'DB'} }[$linenum]->{'type'} ne 'comment'
            && (   $#{ ${ $self->{'DB'} }[$linenum]->{'daemon_list'} } == -1
                || $#{ ${ $self->{'DB'} }[$linenum]->{'client_list'} } == -1 )
        ) {
            next();
        }
        print DBL ${ $self->{'DB'} }[$linenum]->{'contents'} . "\n";
    }
    Cpanel::SafeFile::safeclose( \*DBL, $dbl );

    # Try to empty /etc/hosts.deny
    my $dbl2 = Cpanel::SafeFile::safeopen( \*DBL, '>', $HOSTS_DENY );
    if ( !$dbl ) {
        Cpanel::Debug::log_warn("Could not write to $HOSTS_DENY");
        return;
    }
    return Cpanel::SafeFile::safeclose( \*DBL, $dbl2 );
}

sub parse_host_access_line {
    my $line = shift;
    my $buffer;
    my @LS;
    my $sep    = 0;
    my $escape = 0;
    for my $i ( 0 .. length($line) - 1 ) {
        my $chr = substr( $line, $i, 1 );
        if ( $chr eq '[' ) {
            $sep++;
        }
        elsif ( $chr eq ']' ) {
            $sep--;
        }
        if ( !$escape && $sep == 0 && $chr eq ':' ) {
            push( @LS, $buffer );
            $buffer = '';
            next();
        }
        else {
            $buffer .= $chr;
            $escape = 0;
        }
        if ( $chr eq '\\' ) {
            $escape = 1;
        }

    }

    push( @LS, $buffer );

    s{\A\s+|\s+\z}{}g for @LS;

    return @LS;
}

=head2 add(%args)

The key/value pairs in %args are:

=over

=item * position

String

This parameter determines the position within the file to add the entry.
An allow entry meant to override a broader deny entry must be placed at the
top of the file.

Valid values:

'top' - Place the entry near the top of the file, above the first non-comment
entry. (Any introductory comments for the file will remain above it.)

'bottom' - Place the entry at the bottom of the file.

=item * daemon_list

Array ref

Must contain one or more valid service names. See hosts_access(5).

=item * client_list

Array ref

Must contain one or more valid client specifications. See hosts_access(5).

=item * action_list

Array ref

Must contain one or more valid actions. See hosts_access(5).

=item * comment

String

Any text to be added as a comment. This is required.

=back

Returns: n/a

=cut

sub add {
    my ( $self, %args ) = @_;

    ref $self && $self->isa(__PACKAGE__) || Carp::croak('add() must be called as an instance method');

    my $position    = delete $args{'position'} || Carp::croak('position is required');
    my $daemon_list = delete $args{'daemon_list'};
    'ARRAY' eq ref $daemon_list or Carp::croak('daemon_list is required and must be an array ref');
    my $client_list = delete $args{'client_list'} || Carp::croak('client_list is required');
    'ARRAY' eq ref $client_list or Carp::croak('client_list is required and must be an array ref');
    my $action_list = delete $args{'action_list'} || Carp::croak('action_list is required');
    'ARRAY' eq ref $action_list or Carp::croak('action_list is required and must be an array ref');
    my $comment = delete $args{'comment'} || Carp::croak('comment is required');

    if (%args) {
        Carp::croak( 'Unexpected arguments given to add(): ' . join( ', ', sort keys %args ) );
    }

    my $entry = {
        type        => 'access_list',
        daemon_list => $daemon_list,
        client_list => $client_list,
        action_list => $action_list,
        comment     => $comment,
    };

    if ( 'top' eq $position ) {
        my $top = $self->_find_top();
        splice @{ $self->{'DB'} }, $top, 0, $entry;
    }
    elsif ( 'bottom' eq $position ) {
        push( @{ $self->{'DB'} }, $entry );
    }
    else {
        Carp::croak('position must be either top or bottom');
    }

    return;
}

# Find the index of the first non-comment entry in the file. If there are none,
# or if the top line is not a comment, then the index will be 0.
sub _find_top {
    my ($self) = @_;
    my $top;
    for my $n ( 0 .. $#{ $self->{'DB'} } ) {
        $top = $n;
        last if 'comment' ne ( $self->{'DB'}[$n]{'type'} || '' );
    }
    return $top;
}

=head2 remove_by_comment(COMMENT)

Remove any host access entries that have the specified comment. This is meant for cleaning
up entries that were automatically added.

COMMENT may be any non-empty string, and entries will only be removed if they match it.

Returns: The number of entries removed

=cut

sub remove_by_comment {
    my ( $self, $comment ) = @_;

    $comment || Carp::croak('comment is required');

    my $entries_removed = 0;
    for ( my $i = $#{ $self->{'DB'} }; $i >= 0; $i-- ) {
        if ( ( $self->{'DB'}[$i]{'comment'} || '' ) eq $comment ) {
            splice @{ $self->{'DB'} }, $i, 1;
            ++$entries_removed;
        }
    }

    return $entries_removed;
}

sub has_entry_with_comment {
    my ( $self, $comment ) = @_;

    for my $entry ( @{ $self->{'DB'} } ) {
        if ( ( $entry->{comment} || '' ) eq $comment ) {
            return 1;
        }
    }

    return 0;
}

1;
