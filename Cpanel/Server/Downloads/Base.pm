# cpanel - Cpanel/Server/Downloads/Base.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::Server::Downloads::Base;

use cPstrict;

use parent qw(Cpanel::Server::Handler);

use Cpanel::Features::Check ();

use Cpanel::Imports;

=head1 MODULE

C<Cpanel::Server::Downloads::Base.pm>

=head1 DESCRIPTION

C<Cpanel::Server::Downloads::Base.pm> provides a common base
class for generating downloads.

=head1 SYNOPSIS

  package Cpanel::Server::Downloads::Example;

  use cPstrict;

  use parent qw(Cpanel::Server::Downloads::Base);

  sub new($class, %args) {
      my $self = $class->SUPER::new(@_);

      foreach my $param (qw(another)) {
          $self->verify_required($param, $args{$param});
          $self->{$param} = $args{$param};
      }

      return $self;
  }

  sub serve() {

  }


=head1 CONSTRUCTOR

=cut

sub new ( $class, %args ) {

    my $self = $class->SUPER::new(%args);

    foreach my $param (qw(document user cpconf)) {
        $self->verify_required( $param, $args{$param} );
        $self->{$param} = $args{$param};
    }

    return $self;
}

=head1 PROPERTIES

=head2 INSTANCE->server - Cpanel::Server

The server object for the current request. Provided via cpsrvd normally.

=cut

sub server ($self) {
    return $self->{_server_obj};
}

=head2 INSTANCE->document - string

The document being requested. Provided by cpsrvd usually.

=cut

sub document ($self) {
    return $self->{document};
}

=head2 INSTANCE->user - string

The currently logged in user making the request.

=cut

sub user ($self) {
    return $self->{user};
}

=head2 INSTANCE->cpconf - hashref

The current loaded /var/cpanel/cpanel.config data.

=cut

sub cpconf ($self) {
    return $self->{cpconf};
}

=head1 METHODS

=head2 INSTANCE->serve()

Abstract method to override in subclasses. This is where the code will live to generate and send a download.

=cut

sub serve ($self) {
    die Cpanel::Exception::create('NotImplemented');
}

=head2 INSTANCE->verify_required(PARAM, VALUE)

Helper method to validate the required arguments are initialized.

=head3 ARGUMENTS

=over

=item PARAM - string

Name of the property

=item VALUE - any

Value to validate, must be defined.

=back

=cut

sub verify_required ( $self, $param, $value ) {
    require Cpanel::Exception;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) if !defined $value || $value eq '';
    return 1;
}

=head2 INSTANCE->logaccess(STATUS_CODE)

Generate an access log entry for the requested document.

=head3 ARGUMENTS

=over

=item STATUS_CODE - number

Optional. The HTTP status code. Defaults to 200.

=back

=cut

sub logaccess ( $self, $http_status_code = 200 ) {
    $ENV{'HTTP_STATUS'} = $http_status_code;    # Sets the status code for logging.
    return $self->server()->logaccess();
}

=head2 INSTANCE->memorize_homedir()

Change to the users home directory and keep track of it on the server object.

=cut

sub memorize_homedir ($self) {
    my $homedir = $self->server()->auth()->get_homedir()
      or die _safe_longmess("Failed to get_homedir from the request object");
    return $self->memorize_directory($homedir);
}

=head2 INSTANCE->memorize_directory(DIR)

Change to the directory and keep track of it on the server object.

=head3 ARGUMENTS

=over

=item DIR - string

The directory to change to and memorize.

=back

=cut

sub memorize_directory ( $self, $dir ) {
    if ( !$self->server()->memorized_chdir($dir) ) {
        return $self->server()->internal_error( locale()->maketext( 'The system could not change to the “[_1]” directory and returned the following error: [_2]', $dir, $! ) );
    }
    return;
}

=head2 INSTANCE->check_features(FEATURES)

Check if the user has the needed feature to run the download handler.

=head3 ARGUMENTS

=over

=item FEATURES - array of strings

List of features required by the application handled by the handler.

=back

=cut

sub check_features ( $self, @features ) {
    foreach my $feature (@features) {
        if ( !Cpanel::Features::Check::check_feature_for_user( $self->user(), $feature, $self->server()->auth()->get_featurelist(), $self->server()->auth()->get_features_from_cpdata() ) ) {
            $self->send_401( locale()->maketext('This feature is disabled for this account.') );
            return 0;
        }
    }
    return 1;
}

=head2 INSTANCE->send_401(MESSAGE)

Generate a HTTP 401 Access Denied status response. This will also create an access log entry.

=head3 ARGUMENTS

=over

=item MESSAGE - string

Message to send with the HTTP 500 status response.

=back

=cut

sub send_401 ( $self, $message ) {
    $self->logaccess(401);
    return $self->server()->send_401($message);
}

=head2 INSTANCE->send_404(MESSAGE)

Generate a HTTP 404 Not Found status response. This will also create an access log entry.

=head3 ARGUMENTS

=over

=item MESSAGE - string

Message to send with the HTTP 500 status response.

=back

=cut

sub send_404 ( $self, $message ) {
    $self->logaccess(404);
    return $self->server()->send_404($message);
}

=head2 INSTANCE->internal_error(MESSAGE)

Generate a HTTP 500 status response. This will also create an access log entry.

=head3 ARGUMENTS

=over

=item MESSAGE - string

Message to send with the HTTP 500 status response.

=back

=cut

sub internal_error ( $self, $message ) {
    $self->logaccess(500);
    return $self->server()->internal_error($message);
}

=head2 INSTANCE->send_targz_headers(FILENAME)

Generate a HTTP download header that includes the necessary
encoding headers for a gz archive.

=head3 ARGUMENTS

=over

=item FILENAME - string

Optional, name of the file to add to the download header.

=back

=cut

sub send_targz_headers ( $self, $filename = '' ) {
    my $server = $self->server();
    $server->response()->set_state_sent_headers_to_socket();

    my $buffer = "HTTP/1.1 200 OK\r\n" . "Connection: close\r\n";

    if ( $ENV{'HTTPS'} && $server->request()->get_headers->{'user-agent'} =~ /(?:MSIE|internet explorer)/i ) {    #EVIL IE HACK
        $buffer .= "X-MSIE-WORKAROUND: Caching Not Disabled\r\n";
    }
    else {
        $buffer .= $server->nocache();
    }

    if ($filename) {
        $buffer .= $server->response()->download_content_type_headers( 'application/x-gzip', $filename );
    }
    else {
        $buffer .= "Content-Type: application/x-gzip\r\n";
    }

    $buffer .= "\r\n";
    return $server->connection()->write_buffer( \$buffer );
}

=head1 STATIC METHODS

=head2 _safe_longmess(MESSAGE) [PRIVATE]

Load Carp and call safe_longmess to get the stack in the error.

=cut

sub _safe_longmess {
    require Cpanel::Carp;
    goto \&Cpanel::Carp::safe_longmess;
}

1;
