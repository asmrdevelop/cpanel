package Cpanel::NetDAVServer;

# cpanel - Cpanel/NetDAVServer.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Fcntl      ();
use File::Spec ();
eval "use Encode;";
my $hasencode = $@ ? 0 : 1;
if ( !$hasencode ) {
    unshift @INC, '/usr/local/cpanel/Cpanel/CPAN/stubs/Encode';
    eval "use Encode;";
}
else {
    require utf8;
}
use XML::LibXML               ();
use XML::LibXML::XPathContext ();
use URI::Escape               ();
require Cpanel::CPAN::Net::DAV::Server;
use File::Find::Rule::Filesys::Virtual ();
use Cpanel::Hash                       ();
use Cpanel::DAV::LockManager           ();
use HTTP::Response                     ();
use Cpanel::Encoder::Tiny              ();
use Cpanel::Encoder::URI               ();
use Cpanel::HTTP::Date::Tiny           ();
use Cpanel::Time::HTTP                 ();
use Cpanel::Time::Clf                  ();
use Cpanel::SV                         ();

# TODO - When Net::DAV::Server is corrected, remove this.
$Cpanel::CPAN::Net::DAV::Server::implemented{'proppatch'} = 1;
my @methods = grep { $_ ne 'trace' } keys %Cpanel::CPAN::Net::DAV::Server::implemented;
our %read_only_methods = ( 'propfind' => 1, 'get' => 1, 'head' => 1, 'options' => 1 );    # We only allow methods that are read operations.
                                                                                          # This is the minimum amount of methods needed to browse and download files

my $alarm_wait  = 120;
my $buffer_size = 131070;

# Use larger values for mmap io since
# its much more efficent
my $mmap_io_buffer_size = $buffer_size * 8;
my $mmap_io_alarm_wait  = $alarm_wait * 4;

my @DAV_SUPPORTED = ( '1', '2' );
our @ISA = qw(Cpanel::CPAN::Net::DAV::Server);

sub new {
    my $class = shift;
    my %args  = @_ % 2 ? () : @_;
    my $self  = $class->SUPER::new(@_);
    if ( $args{'-dbobj'} ) {
        $self->{'lock_manager'} = Cpanel::DAV::LockManager->new( $args{'-dbobj'} );
    }
    elsif ( $args{'-dbfile'} ) {
        $self->{'_dsn'} = "dbi:SQLite:dbname=$args{'-dbfile'}";
    }
    elsif ( $args{'-dsn'} ) {
        $self->{'_dsn'} = $args{'-dsn'};
    }
    if ( $args{'-filesys'} ) {
        $self->filesys( $args{'-filesys'} );
    }

    $self->{'perms'} = $args{'perms'} || return;

    $self;
}

# Troubleshoot: Commented out debugging statements can be enabled for troubleshooting.
sub run {
    my ( $self, $request, $response ) = @_;

    if ( $self->{'perms'} ne 'rw' ) {
        my $lc_method = lc $request->method;
        if ( !$read_only_methods{$lc_method} ) {

            #print STDERR $request->method, ': ', $request->uri->path, " -> 405 'Not Allowed in Read-Only mode' {$@}\n";
            return HTTP::Response->new( 405, 'Not Allowed in Read-Only mode' );
        }
    }

    #print STDERR "Method: ", $request->method, ': ', $request->uri->path, "\n";
    $response = eval { $self->SUPER::run( $request, $response ); } or do {
        my $eval = $@;
        $eval =~ s/\n/\t/g;
        print STDERR $request->method, ': ', $request->uri->path, " -> 400 'Bad Request' {$eval}\n";
        return HTTP::Response->new( 400, 'Bad Request' );
    };
    $response->header( 'DAV'           => join( ', ', @DAV_SUPPORTED ) );    # Nautilus freaks out without this
    $response->header( 'MS-Author-Via' => 'DAV' );                           # Nautilus freaks out

    #print STDERR $request->method, ': ', $request->uri->path, ' -> ', $response->code, ' \'', $response->message, "'\n" if !$response->is_success;

    return $response;
}

sub options {
    my ( $self, $request, $response ) = @_;

    # required headers
    $response->header( 'DAV'           => join( ', ', @DAV_SUPPORTED ) );    # Nautilus freaks out without this
    $response->header( 'MS-Author-Via' => 'DAV' );                           # Nautilus freaks out

    $response->header( 'Allow'          => join( ', ', map { uc } @methods ) );    # Vista likes spaces between the commas
    $response->header( 'Content-Type'   => 'text/plain' );
    $response->header( 'Content-Length' => 0 );
    $response->header( 'Keep-Alive'     => 'timeout=15, max=96' );
    return $response;
}

sub get {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, $request, $response ) = @_;
    my $path = URI::Escape::uri_unescape( $request->uri->path );
    my $fs   = $self->filesys;

    my ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks ) = $fs->stat($path);

    if ( defined $mode && Fcntl::S_ISREG($mode) ) {
        if ( $fs->test( 'r', $path ) ) {
            $response->header( 'Content-Type'  => 'application/download' );    #make browsers happy
            $response->header( 'Accept-Ranges' => 'bytes' );                   #apple
            $response->last_modified($mtime);
            $response->{'_filename'} = $path;

            my $if_modified_since = $request->header('If-Modified-Since');
            if ( $if_modified_since && $mtime <= Cpanel::HTTP::Date::Tiny::parse_http_date($if_modified_since) ) {
                $response->message('Not Modified');
                $response->code(304);
                $response->content('');
                $response->header( 'Content-Length' => '0' );    #apple
                $response->{'_length'} = 0;
            }
            else {
                my $ranges   = $request->header('range');
                my $if_range = $request->header('if-range');
                if ( $ranges && ( !$if_range || ( $if_range && $mtime <= Cpanel::HTTP::Date::Tiny::parse_http_date($if_range) ) ) ) {
                    my @RANGES;
                    my $total_range_size;
                    foreach my $range ( split( /\,/, $ranges ) ) {
                        $range =~ s/^bytes=?//;
                        $range =~ s/\/\d+$//;
                        my ( $start, $end ) = split( /-/, $range );

                        if ( !defined $end || $end eq '' ) {
                            $end = $size - 1;
                        }
                        if ( !defined $start || $start eq '' ) {
                            $start = $size - $end;
                            $end   = $size - 1;
                        }
                        if ( $end <= $size && $start >= 0 && $start <= $end ) {
                            push @RANGES, [ $start, $end ];
                            $total_range_size += ( $end - $start + 1 );
                        }
                    }
                    if (@RANGES) {
                        $response->code(206);
                        $response->message('Partial Content');

                        if ( scalar @RANGES == 1 ) {

                            #Single Range
                            my $range = $RANGES[0];
                            $response->header( 'Content-Range' => "bytes " . $range->[0] . '-' . $range->[1] . '/' . $size );
                            $response->content(
                                sub {
                                    my ($http) = @_;
                                    my $buf;
                                    if ( my $fh = $fs->open_read($path) ) {
                                        $fh->seek( $range->[0], 0 );
                                        my $bytes_left = $range->[1] - $range->[0] + 1;
                                        my $bytes_read = 0;
                                        while ( $bytes_read = $fh->read( $buf, ( $bytes_left > $buffer_size ? $buffer_size : $bytes_left ) ) ) {
                                            alarm($alarm_wait);
                                            $http->write_socket( \$buf );
                                            last if ( $bytes_left -= $buffer_size <= 0 || !$bytes_read );
                                        }
                                        $fs->close_read($fh);
                                    }
                                }
                            );
                            $response->{'_length'} = $total_range_size;
                        }
                        else {
                            require Cpanel::Rand::Get;
                            my $boundry = Cpanel::Rand::Get::getranddata(17);
                            $response->header( 'Content-Type' => "multipart/byteranges; boundary=$boundry" );
                            my $content_length = 2;    #"\r\n\r\n"
                            foreach my $range (@RANGES) {
                                $content_length += 21;                                                                                           #-- , $boundry, \r\n
                                $content_length += length("Content-type: application/download\r\n");
                                $content_length += length( "Content-range: bytes " . $range->[0] . '-' . $range->[1] . '/' . $size . "\r\n" );
                                $content_length += 2;                                                                                            #\r\n;
                                $content_length += $range->[1] - $range->[0] + 1;
                                $content_length += 2;                                                                                            #\r\n;
                            }
                            $content_length += 23;                                                                                               #--, $boundry, --, \r\n
                            $response->{'_length'} = $content_length;

                            my $range = $RANGES[0];
                            $response->content(
                                sub {
                                    my ($http) = @_;
                                    $http->write_socket( \"\r\n" );
                                    foreach my $range (@RANGES) {
                                        my $buf;
                                        $http->write_socket( '--' . $boundry . "\r\n" . "Content-type: application/download\r\n" . "Content-range: bytes " . $range->[0] . '-' . $range->[1] . '/' . $size . "\r\n" . "\r\n" );
                                        if ( my $fh = $fs->open_read($path) ) {
                                            $fh->seek( $range->[0], 0 );
                                            my $bytes_left = $range->[1] - $range->[0] + 1;
                                            my $bytes_read = 0;
                                            while ( $bytes_read = $fh->read( $buf, ( $bytes_left > $buffer_size ? $buffer_size : $bytes_left ) ) ) {
                                                alarm($alarm_wait);
                                                $http->write_socket( \$buf );
                                                last if ( $bytes_left -= $buffer_size <= 0 || !$bytes_read );
                                            }
                                            $fs->close_read($fh);
                                        }
                                        $http->write_socket( \"\r\n" );
                                    }
                                    $http->write_socket( \"--$boundry--\r\n" );
                                }
                            );

                        }
                    }
                    else {
                        $response->code(416);
                        $response->message('Requested Range Not Satisfiable');
                        $response->content('');
                        $response->header( 'Content-Length' => '0' );    #apple
                        $response->{'_length'} = $total_range_size;
                    }
                }
                else {
                    $response->content(
                        sub {
                            my ($http) = @_;
                            my $buf;
                            if ( my $fh = $fs->open_read($path) ) {
                                while ( $fh->read( $buf, $mmap_io_buffer_size ) ) {
                                    alarm($mmap_io_alarm_wait);
                                    $http->write_socket( \$buf );
                                }
                                $fs->close_read($fh);
                            }
                        }
                    );

                    # The Content-Length is required for HTTP/1.1
                    $response->header( 'Content-Length' => $size );
                    $response->{'_length'} = $size;    # Since response is a coderef,

                    # we have to tell Cpanel::Httpd the real length of the content due to the hack it uses to avoid
                    # loading the whole response in memory.
                    #
                    # TODO: convert Cpanel::Httpd to make use of Cpanel::Server

                }
            }
        }
        else {
            $response->code(403);
            $response->message('Access Denied');
        }
    }
    elsif ( defined $mode && Fcntl::S_ISDIR($mode) ) {

        # a web browser, then
        my $files_ref = $fs->list($path);

        my $safe_path = Cpanel::Encoder::Tiny::safe_html_encode_str($path);

        # generate an HTML page listing the contents.
        # Includes classes for possibility of better styling
        my $body = << "EOH";
<html>
<head>
   <title>$safe_path</title>
   <style type="text/css">
    th { text-align: left; }
    td.size { text-align: right; }
    .pdir { font-variant: small-caps; }
    .pdir, .dir, .file, .date {
        padding-right: 2em;
    }
    .size {
        padding-left: 2em;
    }
   </style>
</head>
<body>
<h1>Contents of <span class="path">$safe_path</span></h1>
<table>
  <thead>
    <tr><th>Name</th><th>Last Modified</th><th>Size</th></tr>
  </thead>
  <tbody>
EOH
        my ( $mode, $size, $mtime, $modtime );
        foreach my $file ( @{$files_ref} ) {
            next if $file eq '.';
            $file =~ s{/$}{};

            ( $mode, $size, $mtime ) = ( $fs->stat( $path . $file ) )[ 2, 7, 9 ];
            my $safe_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);
            my $link_file = Cpanel::Encoder::URI::uri_encode_str($file);

            # Handle parent links for all directories but the root.
            if ( $file eq '..' ) {
                next if $path eq '/';

                # Maybe want a different representation of the parent directory
                $body .= qq|  <tr><td class="pdir"><a href="$link_file">Parent Directory</a></td>\n<td class="date">&nbsp;</td>\n<td class="size">-</td></tr>\n|;
            }
            elsif ( Fcntl::S_ISDIR($mode) ) {
                $modtime = _modtime($mtime);
                $body .= qq|  <tr><td class="dir"><a href="$link_file/">$safe_file/</a></td>\n<td class="date">$modtime</td><td class="size">-</td></tr>|;
            }
            else {
                $modtime = _modtime($mtime);
                $body .= qq|  <tr><td class="file"><a href="$link_file">$safe_file</a></td>\n<td class="date">$modtime</td><td class="size">$size</td></tr>|;
            }
        }
        $body .= << 'EOF';
    </tbody>
</table>
</body>
</html>
EOF
        $response->header( 'Content-Type' => 'text/html; charset="utf-8"' );
        $response->content($body);
    }
    else {
        $response->code(404);
        $response->message('Not Found');
    }

    return $response;
}

sub _modtime {
    my ($mtime) = @_;
    my ( $sec, $min, $hr, $day, $mon, $yr ) = localtime($mtime);
    $yr += 1900;
    $mon = (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec))[$mon];
    return sprintf '%d-%s-%d %02d:%02d', $day, $mon, $yr, $hr, $min;
}

sub _lock_manager {
    my ($self) = @_;
    unless ( $self->{'lock_manager'} ) {
        if ( $self->{'_dsn'} ) {
            require Cpanel::DAV::LockManager::DB;
            my $db = Cpanel::DAV::LockManager::DB->new( $self->{'_dsn'} );
            $self->{'lock_manager'} = Cpanel::DAV::LockManager->new($db);
        }
        else {
            $self->{'lock_manager'} = Cpanel::DAV::LockManager->new();
        }
    }
    return $self->{'lock_manager'};
}

sub lock {
    my ( $self, $request, $response ) = @_;
    my $lockreq = _parse_lock_request($request);

    # Invalid XML requires a 400 response code.
    return HTTP::Response->new( 400, 'Bad Request' ) unless defined $lockreq;

    if ( !$lockreq->{'has_content'} ) {

        # Not already locked.
        return HTTP::Response->new( 403, 'Forbidden' ) if !$lockreq->{'token'};

        # Reset timeout
        if ( my $lock = $self->_lock_manager()->refresh_lock($lockreq) ) {
            $response->header( 'Content-Type' => 'text/xml; charset="utf-8"' );
            $response->content(
                _lock_response_content(
                    {
                        'path'    => $lock->path,
                        'token'   => $lock->token,
                        'timeout' => $lock->timeout,
                        'scope'   => $lock->scope,
                        'depth'   => $lock->depth,
                    }
                )
            );
        }
        else {
            my $curr = $self->_lock_manager()->find_lock( { 'path' => $lockreq->{'path'} } );
            return HTTP::Response->new( 412, 'Precondition Failed' ) unless $curr;

            # Not the correct lock token
            return HTTP::Response->new( 412, 'Precondition Failed' ) if $lockreq->{'token'} ne $curr->token;

            # Not the correct user.
            return HTTP::Response->new( 403, 'Forbidden' );
        }
        return $response;
    }

    # Validate depth request
    return HTTP::Response->new( 400, 'Bad Request' ) unless $lockreq->{'depth'} =~ m/^(?:[01]|infinity)$/i;

    my $lock = $self->_lock_manager()->lock($lockreq);

    if ( !$lock ) {
        my $curr = $self->_lock_manager()->find_lock( { 'path' => $lockreq->{'path'} } );
        return HTTP::Response->new( 412, 'Precondition Failed' ) unless $curr;

        # Not the correct lock token
        return HTTP::Response->new( 412, 'Precondition Failed' ) if $lockreq->{'token'} ne $curr->token;

        # Resource is already locked
        return HTTP::Response->new( 403, 'Forbidden' );
    }

    my $token = $lock->token;
    $response->header( 'Lock-Token',   "<$token>" );
    $response->header( 'Content-Type', 'text/xml; charset="utf-8"' );
    $response->content(
        _lock_response_content(
            {
                'path'       => $lock->path,
                'token'      => $token,
                'timeout'    => $lock->timeout,
                'scope'      => 'exclusive',
                'depth'      => $lock->depth,
                'owner_node' => $lockreq->{'owner_node'},
            }
        )
    );

    # Create empty file if none exists, as per RFC 4918, Section 9.10.4
    my $fs = $self->filesys;
    if ( !$fs->test( 'e', $lock->path ) ) {
        my $fh = $fs->open_write( $lock->path, 1 );
        $fs->close_write($fh) if $fh;
    }

    return $response;
}

sub _get_timeout {
    my ($to_header) = @_;
    return undef unless defined $to_header and length $to_header;

    my @timeouts = sort
      map  { /Second-(\d+)/ ? $1 : $_ }
      grep { $_ ne 'Infinite' }
      split /\s*,\s*/, $to_header;

    return undef unless @timeouts;
    return $timeouts[0];
}

sub _parse_lock_header {
    my ($req)   = @_;
    my $depth   = $req->header('Depth');
    my %lockreq = (
        'path' => URI::Escape::uri_unescape( $req->uri->path ),

        #fallback is basic auth
        'user'    => $ENV{'REMOTE_USER'} || ( $req->authorization_basic() )[0],
        'token'   => ( _extract_lock_token($req) || undef ),
        'timeout' => _get_timeout( $req->header('Timeout') ),
        'depth'   => ( defined $depth ? $depth : 'infinity' ),
    );
    return \%lockreq;
}

sub _parse_lock_request {
    my ($req) = @_;
    my $lockreq = _parse_lock_header($req);
    return $lockreq unless $req->content;

    my $parser          = XML::LibXML->new();
    my $input_callbacks = XML::LibXML::InputCallback->new();
    $input_callbacks->register_callbacks( [ \&xml_match, \&xml_open, \&xml_read, \&xml_close ] );
    $parser->input_callbacks($input_callbacks);

    my $doc;
    eval { $doc = $parser->parse_string( $req->content ); } or do {

        # Request body must be a valid XML request
        return;
    };
    my $xpc = XML::LibXML::XPathContext->new($doc);
    $xpc->registerNs( 'a', 'DAV:' );    # this used to be 'D', however windows vista choked on this for some unknown black box reason.

    # Want the following in list context.
    $lockreq->{'owner_node'} = ( $xpc->findnodes('/a:lockinfo/a:owner') )[0];
    if ( $lockreq->{'owner_node'} ) {
        my $owner = $lockreq->{'owner_node'}->toString;
        $owner =~ s/^<(?:[^:]+:)?owner>//sm;
        $owner =~ s!</(?:[^:]+:)?owner>$!!sm;
        $lockreq->{'owner'} = $owner;
    }
    $lockreq->{'scope'}       = eval { ( $xpc->findnodes('/a:lockinfo/a:lockscope/a:*') )[0]->localname; };
    $lockreq->{'has_content'} = 1;

    return $lockreq;
}

sub _extract_lock_token {
    my ($req) = @_;
    my $token = $req->header('If');
    unless ($token) {
        $token = $req->header('Lock-Token');
        return $1 if defined $token && $token =~ /<([^>]+)>/;
        return undef;
    }

    # Based on the last paragraph of section 10.4.1 of RFC 4918, it appears
    # that any lock token that appears in the If header is available as a
    # known lock token. Rather than trying to deal with the whole entity,
    # lock, implicit and/or, and Not (with and without resources) thing,
    # This code just returns a list of lock tokens found in the header.
    my @tokens = map { $_ =~ /<([^>]+)>/g } ( $token =~ /\(([^\)]+)\)/g );

    return undef unless @tokens;
    return @tokens == 1 ? $tokens[0] : \@tokens;
}

sub _lock_response_content {
    my ($args) = @_;
    my $resp   = XML::LibXML::Document->new( '1.0', 'utf-8' );
    my $prop   = _dav_root( $resp, 'prop' );
    my $lock   = _dav_child( _dav_child( $prop, 'lockdiscovery' ), 'activelock' );
    _dav_child( _dav_child( $lock, 'locktype' ), 'write' );
    _dav_child( _dav_child( $lock, 'lockscope' ), $args->{'scope'} || 'exclusive' );
    _dav_child( $lock, 'depth', $args->{'depth'} || 'infinity' );
    if ( $args->{'owner_node'} ) {
        my $owner = $args->{'owner_node'}->cloneNode(1);
        $resp->adoptNode($owner);
        $lock->addChild($owner);
    }
    _dav_child( $lock, 'timeout', "Second-$args->{'timeout'}" );
    _dav_child( _dav_child( $lock, 'locktoken' ), 'href', $args->{'token'} );
    _dav_child( _dav_child( $lock, 'lockroot' ),  'href', $args->{'path'} );

    return $resp->toString;
}

sub _active_lock_prop {
    my ( $doc, $lock ) = @_;
    my $active = $doc->createElement('a:activelock');

    # All locks are write
    _dav_child( _dav_child( $active, 'locktype' ),  'write' );
    _dav_child( _dav_child( $active, 'lockscope' ), $lock->scope );
    _dav_child( $active, 'depth', $lock->depth );
    $active->appendWellBalancedChunk( '<D:owner xmlns:D="DAV:">' . $lock->owner . '</D:owner>' );
    _dav_child( $active, 'timeout', 'Second-' . $lock->timeout );
    _dav_child( _dav_child( $active, 'locktoken' ), 'href', $lock->token );
    _dav_child( _dav_child( $active, 'lockroot' ),  'href', $lock->path );

    return $active;
}

sub unlock {
    my ( $self, $request ) = @_;
    my $path    = URI::Escape::uri_unescape( $request->uri->path );
    my $lockreq = _parse_lock_header($request);

    # No lock token supplied, we cannot unlock
    return HTTP::Response->new( 400, 'Bad Request' ) unless $lockreq->{'token'};

    if ( !$self->_lock_manager()->unlock($lockreq) ) {
        my $curr = $self->_lock_manager()->find_lock( { 'path' => $lockreq->{'path'} } );

        # No lock exists, conflicting requirements.
        return HTTP::Response->new( 409, 'Conflict' ) unless $curr;

        # Not the owner of the lock or bad token.
        return HTTP::Response->new( 403, 'Forbidden' );
    }

    return HTTP::Response->new( 204, 'No content' );
}

sub _dav_child {
    my ( $parent, $tag, $text ) = @_;
    my $child = $parent->ownerDocument->createElement("a:$tag");
    $parent->addChild($child);
    $child->appendText($text) if defined $text;
    return $child;
}

sub _dav_root {
    my ( $doc, $tag ) = @_;
    my $root = $doc->createElementNS( 'DAV:', $tag );
    $root->setNamespace( 'DAV:', 'a', 1 );    # this used to be 'D', however windows vista choked on this for some unknown black box reason.
    $doc->setDocumentElement($root);
    return $root;
}

sub _can_modify {
    my ( $self, $request ) = @_;
    my $lockreq = _parse_lock_header($request);
    return $self->_lock_manager()->can_modify($lockreq);
}

sub put {
    my ( $self, $request, $response ) = @_;

    if ( !$self->_can_modify($request) ) {
        return HTTP::Response->new( 403, 'Forbidden' );
    }
    my $path = URI::Escape::uri_unescape( $request->uri->path );
    my $fs   = $self->filesys;

    my $fh = $fs->open_write($path);
    if ( !$fh ) {
        return HTTP::Response->new( 409, 'Conflict' );
    }
    my $writeref = $request->content;
    if ( ref $writeref ne 'CODE' ) {
        return HTTP::Response->new( 500, 'Internal Server Error' );
    }
    &$writeref($fh);

    # TODO - add error checking
    $fs->close_write($fh);
    return HTTP::Response->new( 201, 'Created', $response->headers, 'Resource Created' );
}

sub post {
    my ( $self, $request, $response ) = @_;

    if ( !$self->_can_modify($request) ) {
        return HTTP::Response->new( 403, 'Forbidden' );
    }

    # Saying it isn't implemented is better than crashing!
    warn "POST not implemented\n";
    $response->code(501);
    $response->message('Not Implemented');

    return $response;
}

sub propfind {
    my ( $self, $request, $response ) = @_;
    my $path  = URI::Escape::uri_unescape( $request->uri->path );
    my $fs    = $self->filesys;
    my $depth = $request->header('Depth');

    my $reqinfo = 'allprop';
    my @reqprops;
    if ( $request->header('Content-Length') ) {
        my $content = $request->content;

        my $parser          = XML::LibXML->new();
        my $input_callbacks = XML::LibXML::InputCallback->new();
        $input_callbacks->register_callbacks( [ \&xml_match, \&xml_open, \&xml_read, \&xml_close ] );
        $parser->input_callbacks($input_callbacks);

        my $doc;
        eval { $doc = $parser->parse_string($content); };
        if ($@) {
            $response->code(400);
            $response->message('Bad Request');
            return $response;
        }

        #$reqinfo = doc->find('/DAV:propfind/*')->localname;
        $reqinfo = $doc->find('/*/*')->shift->localname;
        if ( $reqinfo eq 'prop' ) {

            #for my $node ($doc->find('/DAV:propfind/DAV:prop/*')) {
            for my $node ( $doc->find('/*/*/*')->get_nodelist ) {
                push @reqprops, [ $node->namespaceURI, $node->localname ];
            }
        }
    }
    my @cached_path_stat = $fs->stat($path);
    my $cached_path      = $path;
    my $path_mode        = $cached_path_stat[2];
    if ( !$path_mode ) {
        $response->code(404);
        $response->message('Not Found');
        return $response;
    }

    $response->code(207);
    $response->message('Multi-Status');

    # TODO - Change to application/xml if HTTP::DAV is ever fixed.
    # If this header is correct, HTTP::DAV cannot do ls properly.
    $response->header( 'Content-Type' => 'text/xml; charset="utf-8"' );

    my $doc       = XML::LibXML::Document->new( '1.0', 'utf-8' );
    my $multistat = $doc->createElement('a:multistatus');
    $multistat->setAttribute( 'xmlns:b', 'urn:uuid:c2f41010-65b3-11d1-a29f-00aa00c14882/' );
    $multistat->setAttribute( 'xmlns:c', 'xml:' );
    $multistat->setAttribute( 'xmlns:a', 'DAV:' );
    $multistat->setAttribute( 'xmlns:Z', 'urn:schemas-microsoft-com:' );
    $doc->setDocumentElement($multistat);

    unless ( $reqinfo eq 'propname' ) {

        # Force a load of the locks database so we can do $Cpanel::DAV::LockManager::USE_CACHE below
        $self->_lock_manager()->_get_lock($path);
    }

    my @paths;
    if ( defined $depth && $depth eq 1 && Fcntl::S_ISDIR($path_mode) ) {
        my $p = $path;
        $p .= '/' unless $p =~ m{/$};
        @paths = map { $p . $_ } File::Spec->no_upwards( $fs->list($path) );
        unshift @paths, $path;
    }
    else {
        @paths = ($path);
    }

    for my $path (@paths) {
        my ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks );

        if ( $cached_path eq $path ) {
            ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks ) = @cached_path_stat;

        }
        else {
            ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks ) = $fs->stat($path);
        }
        my $is_dir = Fcntl::S_ISDIR($mode);

        # modified time is stringified human readable HTTP::Date style
        $mtime = Cpanel::Time::HTTP::time2http($mtime);
        $ctime = Cpanel::Time::Clf::time2utctime($ctime) . '.000Z';
        $size ||= '';

        my $resp = $doc->createElement('a:response');
        $multistat->addChild($resp);
        my $href     = $doc->createElement('a:href');
        my $filename = File::Spec->catdir( map { URI::Escape::uri_escape($_) } File::Spec->splitdir($path) );
        $filename =~ s/\/$//;

        $href->appendText($filename);
        $resp->addChild($href);
        $href->appendText('/') if $is_dir;

        my $okprops = $doc->createElement('a:prop');
        my $nfprops = $doc->createElement('a:prop');
        my $prop;

        if ( $reqinfo eq 'prop' ) {
            my %prefixes = ( 'DAV:' => 'a', 'urn:schemas-microsoft-com:' => 'Z' );    # 'a' used to be 'D', however windows vista choked on this for some unknown black box reason.
            my $i        = 0;

            for my $reqprop (@reqprops) {
                my ( $ns, $name ) = @$reqprop;

                if ( $name eq 'Win32AccessTime' ) {
                    $prop = $doc->createElement('Z:Win32AccessTime');
                    $prop->appendText( strftime( '%a, %d %b %Y %T GMT', gmtime($atime) ) );
                    $okprops->addChild($prop);
                }
                elsif ( $name eq 'Win32ModifiedTime' ) {
                    $prop = $doc->createElement('Z:Win32ModifiedTime');
                    $prop->appendText( strftime( '%a, %d %b %Y %T GMT', gmtime($mtime) ) );
                    $okprops->addChild($prop);
                }
                elsif ( $name eq 'Win32CreationTime' ) {
                    $prop = $doc->createElement('Z:Win32CreationTime');
                    $prop->appendText( strftime( '%a, %d %b %Y %T GMT', gmtime($ctime) ) );
                    $okprops->addChild($prop);
                }
                elsif ( $name eq 'Win32FileAttributes' ) {
                    $prop = $doc->createElement('Z:Win32FileAttributes');
                    my $file_attributes = 32 + 128;    #1 = ro, 2= hidden, 4= sys, 32=archive, 128 =normal
                    if ( $filename =~ m/^\./ ) {
                        $file_attributes += 2;
                    }
                    $prop->appendText( sprintf( "%08x", $file_attributes ) );
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'getetag' ) {
                    $prop = $doc->createElement('a:getetag');
                    $prop->appendText( Cpanel::Hash::get_fastest_hash( $path . ( $size || 0 ) . ( $mtime || 0 ) ) );
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'getcontentlength' ) {
                    $prop = $doc->createElement('a:getcontentlength');
                    $prop->setAttribute( 'b:dt', 'int' );
                    $prop->appendText( int $size );    # nautilus crashes on an EMPTY value (0 is ok)
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'creationdate' ) {
                    $prop = $doc->createElement('a:creationdate');
                    $prop->setAttribute( 'b:dt', 'dateTime.tz' );
                    $prop->appendText($ctime);
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'getcontenttype' ) {
                    $prop = $doc->createElement('a:getcontenttype');
                    if ($is_dir) {
                        $prop->appendText('httpd/unix-directory');
                    }
                    else {
                        $prop->appendText('httpd/unix-file');
                    }
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'getlastmodified' ) {
                    $prop = $doc->createElement('a:getlastmodified');
                    $prop->setAttribute( 'b:dt', 'dateTime.rfc1123' );
                    $prop->appendText($mtime);
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'resourcetype' ) {
                    $prop = $doc->createElement('a:resourcetype');
                    if ($is_dir) {
                        my $col = $doc->createElement('a:collection');
                        $prop->addChild($col);
                    }
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'supportedlock' ) {
                    $prop = _supportedlock_child($okprops);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'ishidden' ) {
                    $prop = $doc->createElement('a:ishidden');
                    $prop->setAttribute( 'b:dt', 'boolean' );
                    if ( substr( File::Spec->no_upwards($path), 0, 1 ) eq '.' ) {
                        $prop->appendText('1');
                    }
                    else {
                        $prop->appendText('0');
                    }
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'iscollection' ) {
                    $prop = $doc->createElement('a:iscollection');
                    $prop->setAttribute( 'b:dt', 'boolean' );
                    if ($is_dir) {
                        $prop->appendText('1');
                    }
                    else {
                        $prop->appendText('0');
                    }
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'isfolder' ) {
                    $prop = $doc->createElement('a:isfolder');
                    if ($is_dir) {
                        $prop->appendText('1');
                    }
                    else {
                        $prop->appendText('0');
                    }
                    $okprops->addChild($prop);
                }
                elsif ( $ns eq 'DAV:' && $name eq 'lockdiscovery' ) {
                    $prop = $doc->createElement('a:lockdiscovery');
                    my $user = $ENV{'REMOTE_USER'} || ( $request->authorization_basic() )[0] || '';
                    foreach my $lock ( $self->_lock_manager()->list_all_locks( { 'path' => $path, 'user' => $user }, $Cpanel::DAV::LockManager::USE_CACHE ) ) {
                        my $active = _active_lock_prop( $doc, $lock );
                        $prop->addChild($active);
                    }
                    $okprops->addChild($prop);
                }
                else {
                    my $prefix = $prefixes{$ns};
                    if ( !defined $prefix ) {
                        $prefix = 'i' . $i++;

                        # mod_dav sets <response> 'xmlns' attribute - whatever
                        #$nfprops->setAttribute("xmlns:$prefix", $ns);
                        $resp->setAttribute( "xmlns:$prefix", $ns );

                        $prefixes{$ns} = $prefix;
                    }

                    $prop = $doc->createElement("$prefix:$name");
                    $nfprops->addChild($prop);
                }
            }
        }
        elsif ( $reqinfo eq 'propname' ) {
            _dav_child( $okprops, 'getetag' );
            _dav_child( $okprops, 'getcontentlength' );
            _dav_child( $okprops, 'creationdate' );
            _dav_child( $okprops, 'getcontenttype' );
            _dav_child( $okprops, 'getlastmodified' );
            _dav_child( $okprops, 'resourcetype' );
            _dav_child( $okprops, 'supportedlock' );
            _dav_child( $okprops, 'ishidden' );
            _dav_child( $okprops, 'iscollection' );

        }
        else {
            $prop = $doc->createElement('a:getcontentlength');
            $prop->setAttribute( 'b:dt', 'int' );
            $prop->appendText( int $size );    # nautilus crashes on an EMPTY value (0 is ok)
            $okprops->addChild($prop);

            $prop = $doc->createElement('a:creationdate');
            $prop->setAttribute( 'b:dt', 'dateTime.tz' );
            $prop->appendText($ctime);
            $okprops->addChild($prop);

            $prop = $doc->createElement('a:getcontenttype');
            if ($is_dir) {
                $prop->appendText('httpd/unix-directory');
            }
            else {
                $prop->appendText('httpd/unix-file');
            }
            $okprops->addChild($prop);

            $prop = $doc->createElement('a:getlastmodified');
            $prop->setAttribute( 'b:dt', 'dateTime.rfc1123' );
            $prop->appendText($mtime);
            $okprops->addChild($prop);

            $prop = $doc->createElement('a:resourcetype');
            if ($is_dir) {
                my $col = $doc->createElement('a:collection');
                $prop->addChild($col);
            }
            $okprops->addChild($prop);

            $prop = _supportedlock_child($okprops);
            my $user  = $ENV{'REMOTE_USER'} || ( $request->authorization_basic() )[0] || '';
            my @locks = $self->_lock_manager()->list_all_locks( { 'path' => $path, 'user' => $user }, $Cpanel::DAV::LockManager::USE_CACHE );

            if (@locks) {
                $prop = $doc->createElement('a:lockdiscovery');
                foreach my $lock (@locks) {
                    my $active = _active_lock_prop( $doc, $lock );
                    $prop->addChild($active);
                }
                $okprops->addChild($prop);
            }

            $prop = $doc->createElement('a:ishidden');
            $prop->setAttribute( 'b:dt', 'boolean' );
            if ( substr( File::Spec->no_upwards($path), 0, 1 ) eq '.' ) {
                $prop->appendText('1');
            }
            else {
                $prop->appendText('0');
            }
            $okprops->addChild($prop);
            $prop = $doc->createElement('a:iscollection');
            $prop->setAttribute( 'b:dt', 'boolean' );
            if ($is_dir) {
                $prop->appendText('1');
            }
            else {
                $prop->appendText('0');
            }
            $okprops->addChild($prop);

        }

        if ( $okprops->hasChildNodes ) {
            my $propstat = $doc->createElement('a:propstat');
            my $stat     = $doc->createElement('a:status');
            $stat->appendText('HTTP/1.1 200 OK');
            $propstat->addChild($stat);
            $propstat->addChild($okprops);
            $resp->addChild($propstat);
        }

        if ( $nfprops->hasChildNodes ) {
            my $propstat = $doc->createElement('a:propstat');
            my $stat     = $doc->createElement('a:status');
            $stat->appendText('HTTP/1.1 404 Not Found');
            $propstat->addChild($stat);
            $propstat->addChild($nfprops);
            $resp->addChild($propstat);
        }
    }

    return $self->_send_variable_xml_response( $request, $response, $doc );
}

sub _send_variable_xml_response {
    my ( $self, $request, $response, $doc ) = @_;
    my $xml;
    my $xml_ref = \$xml;

    #this must be 0 as certin ms webdav clients choke on 1
    ${$xml_ref} = $XML::LibXML::Document::{'_toString'} ? $doc->_toString(0) : $doc->toString(0);

    # Get rid of this to prevent us from allocating memory as soon as possible
    undef $doc;

    my $user_agent      = $request->header('User-Agent');
    my $accept_encoding = $request->header('Accept-Encoding');
    if ( ( $accept_encoding && $accept_encoding =~ m/chunked/i ) || ( $user_agent && $user_agent =~ m/darwin/i ) ) {
        $response->{'_length'} = -1;
        $response->header( 'Transfer-Encoding' => 'chunked' );
        $response->content(
            sub {
                my ($http) = @_;
                my $buf;
                while ( length( $buf = substr( ${$xml_ref}, 0, $buffer_size, '' ) ) ) {
                    alarm($alarm_wait);
                    $http->write_socket( sprintf( "%x\r\n", length($buf) ) . $buf . "\r\n" . ( !length $$xml_ref ? "0\r\n\r\n" : '' ) );
                }
            }
        );
    }
    else {
        $response->content($$xml_ref);
    }
    return $response;
}

sub proppatch {
    my ( $self, $request, $response ) = @_;
    my $path = URI::Escape::uri_unescape( $request->uri->path );

    my $proppatchreq = _parse_proppatch_request($request);

    return HTTP::Response->new( 400, 'Bad Request' ) unless defined $proppatchreq;

    if ( $proppatchreq->{'has_content'} ) {
        my $path = $proppatchreq->{'path'};
        my $fs   = $self->filesys;
        my ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks ) = $fs->stat($path);

        return HTTP::Response->new( 404, 'Not Found' ) unless defined $mode;

        my $is_dir = Fcntl::S_ISDIR($mode);

        $response->code(207);
        $response->message('Multi-Status');

        # TODO - Change to application/xml if HTTP::DAV is ever fixed.
        # If this header is correct, HTTP::DAV cannot do ls properly.
        $response->header( 'Content-Type' => 'text/xml; charset="utf-8"' );

        my $doc       = XML::LibXML::Document->new( '1.0', 'utf-8' );
        my $multistat = $doc->createElement('a:multistatus');
        $multistat->setAttribute( 'xmlns:b', 'urn:uuid:c2f41010-65b3-11d1-a29f-00aa00c14882/' );
        $multistat->setAttribute( 'xmlns:c', 'xml:' );
        $multistat->setAttribute( 'xmlns:a', 'DAV:' );
        $multistat->setAttribute( 'xmlns:Z', 'urn:schemas-microsoft-com:' );
        $doc->setDocumentElement($multistat);

        my $resp = $doc->createElement('a:response');
        $multistat->addChild($resp);
        my $href     = $doc->createElement('a:href');
        my $filename = File::Spec->catdir( map { URI::Escape::uri_escape($_) } File::Spec->splitdir($path) );
        $filename =~ s/\/$//;

        $href->appendText($filename);
        $resp->addChild($href);
        $href->appendText('/') if $is_dir;    # THIS MIGHT NOT BE OK FOR VISTA
        my $ns;
        my $propstat = $doc->createElement('a:propstat');
        my $status   = $doc->createElement('a:status');
        $status->appendText('HTTP/1.1 200 OK');
        $propstat->addChild($status);
        my $prop = $doc->createElement('a:prop');

        foreach my $reqprop ( @{ $proppatchreq->{'props'} } ) {
            if ( $reqprop->[1] =~ /^Win32/ ) {
                $ns = 'Z';
            }
            else {
                $ns = 'a';    # 'a' used to be 'D', however windows vista choked on this for some unknown black box reason.
            }
            my $theprop = $doc->createElement( $ns . ':' . $reqprop->[1] );

            #    $theprop->appendText($reqprop->[2]);
            $prop->addChild($theprop);
        }
        $propstat->addChild($prop);
        $resp->addChild($propstat);

        return $self->_send_variable_xml_response( $request, $response, $doc );
    }

    return HTTP::Response->new( 400, 'Bad Request' );
}

sub _parse_proppatch_request {
    my ($req) = @_;
    my $proppatchreq = _parse_lock_header($req);
    return $proppatchreq unless $req->content;

    my $reqinfo = 'allprop';
    my @reqprops;
    if ( $req->header('Content-Length') ) {
        my $parser          = XML::LibXML->new();
        my $input_callbacks = XML::LibXML::InputCallback->new();
        $input_callbacks->register_callbacks( [ \&xml_match, \&xml_open, \&xml_read, \&xml_close ] );
        $parser->input_callbacks($input_callbacks);

        my $doc;
        eval { $doc = $parser->parse_string( $req->content ); } or do {

            # Request body must be a valid XML request
            return;
        };
        if ($@) {
            return;
        }
        $reqinfo = $doc->find('/*/*/*')->shift->localname;
        if ( $reqinfo eq 'prop' ) {
            for my $node ( $doc->find('/*/*/*/*')->get_nodelist ) {
                push @reqprops, [ $node->namespaceURI, $node->localname, $node->textContent ];

                #ex  [            'urn:schemas-microsoft-com:',                        'Win32FileAttributes',                                    '00000020'                                              ]
            }
        }
    }

    $proppatchreq->{'props'}       = \@reqprops;
    $proppatchreq->{'has_content'} = 1;

    return $proppatchreq;
}

sub mkcol {
    my ( $self, $request, $response ) = @_;
    my $path = URI::Escape::uri_unescape( $request->uri->path );

    if ( !$self->_can_modify($request) ) {
        return HTTP::Response->new( 403, 'Forbidden' );
    }

    my $fs = $self->filesys;

    if ( $request->content ) {
        $response->code(415);
        $response->message('Unsupported Media Type');
    }
    elsif ( not $fs->test( "e", $path ) ) {
        $fs->mkdir($path);
        if ( $fs->test( "d", $path ) ) {
            $response->code(201);
            $response->message('Created');
        }
        else {
            $response->code(409);
            $response->message('Conflict');
        }
    }
    else {
        $response->code(405);
        $response->message('Method Not Allowed');
    }
    return $response;
}

sub _get_files {
    my ( $fs, $path, $depth ) = @_;

    return __get_files_or_dirs_ar( $fs, 'file', $path, $depth );
}

sub __get_files_or_dirs_ar {
    my ( $fs, $what_to_get, $path, $depth ) = @_;

    Cpanel::SV::untaint($path);

    my $obj = File::Find::Rule::Filesys::Virtual->virtual($fs)->$what_to_get();
    if ( $depth =~ m{\A[0-9]+\z} ) {
        $obj = $obj->maxdepth($depth);
    }

    my @items = $obj->in($path);

    for my $f (@items) {
        $f =~ tr{/+}{}s;

        if ( substr( $f, -1 ) eq '/' ) {
            substr( $f, -1 ) = q<>;
        }

        Cpanel::SV::untaint($f);
    }

    return reverse @items;
}

sub _get_dirs {
    my ( $fs, $path, $depth ) = @_;

    my @dirs = grep { substr( $_, 0, -2 ) ne '/.' && substr( $_, 0, -3 ) ne '/..' } __get_files_or_dirs_ar( $fs, 'directory', $path, $depth );

    @dirs = sort @dirs;

    return @dirs;
}

sub delete {
    my ( $self, $request, $response ) = @_;
    my $path = URI::Escape::uri_unescape( $request->uri->path );

    if ( !$self->_can_modify($request) ) {
        return HTTP::Response->new( 403, 'Forbidden' );
    }

    my $fs = $self->filesys;

    if ( $request->uri->fragment ) {
        return HTTP::Response->new( 404, "NOT FOUND", $response->headers );
    }

    unless ( $fs->test( "e", $path ) ) {
        return HTTP::Response->new( 404, "NOT FOUND", $response->headers );
    }

    my $dom = XML::LibXML::Document->new( "1.0", "utf-8" );
    my @error;

    # see rt 46865: files first since rmdir() only removed empty directories
    foreach my $part ( _get_files( $fs, $path ), _get_dirs( $fs, $path ), $path ) {
        my ($mode) = ( $fs->stat($part) )[2];

        next unless $mode;

        if ( Fcntl::S_ISREG($mode) ) {
            push @error, _delete_xml( $dom, $part )
              unless $fs->delete($part);
        }
        elsif ( Fcntl::S_ISDIR($mode) ) {
            push @error, _delete_xml( $dom, $part )
              unless $fs->rmdir($part);
        }
    }

    if (@error) {
        my $multistatus = $dom->createElement("a:multistatus");
        $multistatus->setAttribute( "xmlns:D", "DAV:" );

        $multistatus->addChild($_) foreach @error;

        $response = HTTP::Response->new( 207 => "Multi-Status" );
        $response->header( "Content-Type" => 'text/xml; charset="utf-8"' );
    }
    else {
        $response = HTTP::Response->new( 204 => "No Content" );
    }
    return $response;
}

sub _delete_xml {
    my ( $dom, $path ) = @_;

    my $response = $dom->createElement("a:response");
    $response->appendTextChild( "a:href"   => $path );
    $response->appendTextChild( "a:status" => "HTTP/1.1 401 Permission Denied" );    # *** FIXME ***
}

sub copy {
    my ( $self, $request, $response, $op ) = @_;
    my $path = URI::Escape::uri_unescape( $request->uri->path );

    # need to modify request to pay attention to destination address.
    my $lockreq = _parse_lock_header($request);
    $lockreq->{'path'} = URI::Escape::uri_unescape( $request->header('Destination') );
    if ( !$self->_lock_manager()->can_modify($lockreq) ) {
        return HTTP::Response->new( 403, 'Forbidden' );
    }

    $path =~ s{/+$}{};    # see rt 46865
    $op ||= 'copy';

    my $fs       = $self->filesys;
    my $src_mode = ( $fs->stat($path) )[2];
    if ( !$src_mode ) {
        return HTTP::Response->new( 404, 'Not found' );
    }

    my $destination = $request->header('Destination');
    $destination = URI::Escape::uri_unescape( URI->new($destination)->path );
    $destination =~ s{/+$}{};    # see rt 46865

    my $depth = $request->header('Depth');
    $depth = '' if !defined $depth;

    my $overwrite = $request->header('Overwrite') || 'T';    #per spec

    if ( Fcntl::S_ISREG($src_mode) ) {
        return $self->_copy_file( $request, $response, $op );
    }

    my $destexists = $self->filesys->test( "e", $destination );
    if ( ( !$depth || $depth =~ m/^infinity$/i ) && $op eq 'move' && !$destexists ) {    # Just move the whole directory (probably with rename)
        unless ( $fs->move( $path, $destination ) ) {
            $response->code(409);
            $response->message('Conflict');
            return $response;
        }
        $response->{'needs_delete_after_copy'} = 0 if $op eq 'move';
    }
    else {                                                                               # handle Depth
        my @files = _get_files( $fs, $path, $depth );
        my @dirs  = _get_dirs( $fs, $path, $depth );

        push @dirs, $path;
        foreach my $dir ( sort @dirs ) {
            my $destdir = $dir;
            $destdir =~ s/^\Q$path\E/$destination/;
            if (
                $path ne $dir

                # cPanel FIXME::FIXED CASE#? if the path is the dir it is ok as we are copying in the files
                && $overwrite eq 'F'
                && $fs->test( "e", $destdir, 1 )
            ) {
                return HTTP::Response->new( 401, "ERROR", $response->headers );
            }
            $fs->mkdir($destdir);
        }
        foreach my $file ( reverse sort @files ) {
            my $destfile = $file;
            $destfile =~ s/^\Q$path\E/$destination/;
            if ( $fs->test( "e", $destfile ) ) {
                if ( $overwrite eq 'T' ) {
                    $op eq 'move' ? $fs->move( $file, $destfile ) : $fs->copy( $file, $destfile );
                }
                else {

                }
            }
            else {
                $op eq 'move' ? $fs->move( $file, $destfile ) : $fs->copy( $file, $destfile );
            }
        }
    }

    $response->code(201);
    $response->message('Created');
    return $response;
}

sub move {
    my ( $self, $request, $response ) = @_;

    # need to check both paths for locks.
    my $lockreq = _parse_lock_header($request);
    if ( !$self->_lock_manager()->can_modify($lockreq) ) {
        return HTTP::Response->new( 403, 'Forbidden' );
    }

    # No Need to check this as it gets checked in our call to ->copy
    #$lockreq->{'path'} = URI::Escape::uri_unescape( $request->header('Destination') );
    #    if ( !$self->_lock_manager()->can_modify($lockreq) ) {
    #        return HTTP::Response->new( 403, 'Forbidden' );
    #    }

    my $destination = $request->header('Destination');
    $destination = URI::Escape::uri_unescape( URI->new($destination)->path );

    $response->{'needs_delete_after_copy'} = 1;

    $response = $self->copy( $request, $response, 'move' );

    if ( $response->{'needs_delete_after_copy'} ) {
        $response = $self->delete( $request, $response )
          if $response->is_success;
    }

    delete $response->{'needs_delete_after_copy'};
    return $response;
}

sub trace {
    my ($self) = @_;
    return HTTP::Response->new( 501, 'Not implemented' );
}

sub _copy_file {
    my ( $self, $request, $response, $op ) = @_;
    my $path = URI::Escape::uri_unescape( $request->uri->path );
    my $fs   = $self->filesys;

    $op ||= 'copy';
    my $destination = $request->header('Destination');
    $destination = URI::Escape::uri_unescape( URI->new($destination)->path );
    my $depth     = $request->header('Depth');
    my $overwrite = $request->header('Overwrite') || 'T';    #per spec

    if ( $fs->test( "d", $destination ) ) {
        $response = HTTP::Response->new( 204, "NO CONTENT", $response->headers );
    }
    elsif ( $fs->test( "f", $path ) && $fs->test( "r", $path ) ) {
        my ( $mode, $size ) = ( $fs->stat($destination) )[ 2, 7 ];
        if ( Fcntl::S_ISREG($mode) ) {
            if ( !$size || $overwrite eq 'T' ) {
                if ( $op eq 'copy' ) {
                    unless ( $fs->copy( $path, $destination ) ) {
                        $response->code(409);
                        $response->message('Conflict');
                        return $response;
                    }
                }
                else {
                    unless ( $fs->move( $path, $destination ) ) {
                        $response->code(409);
                        $response->message('Conflict');
                        return $response;
                    }
                    $response->{'needs_delete_after_copy'} = 0;
                }
            }
            else {
                $response->code(412);
                $response->message('Precondition Failed');
            }
        }
        else {
            if ( $op eq 'copy' ) {
                unless ( $fs->copy( $path, $destination ) ) {
                    $response->code(409);
                    $response->message('Conflict');
                    return $response;
                }
            }
            else {
                unless ( $fs->move( $path, $destination ) ) {
                    $response->code(409);
                    $response->message('Conflict');
                    return $response;
                }
                $response->{'needs_delete_after_copy'} = 0;
            }
            $response->code(201);
            $response->message('Created');
        }
    }
    else {
        $response->code(404);
        $response->message('Not Found');
    }
    return $response;
}

sub _supportedlock_child {
    my ($okprops) = @_;
    my $prop = _dav_child( $okprops, 'supportedlock' );

    #for my $n (qw(exclusive shared)) {  # shared is currently not supported.
    for my $n (qw(exclusive)) {
        my $lock = _dav_child( $prop, 'lockentry' );

        _dav_child( _dav_child( $lock, 'lockscope' ), $n );
        _dav_child( _dav_child( $lock, 'locktype' ),  'write' );
    }

    return $prop;
}

# Case SEC-32
# These are callbacks for XML::LibXML.
# We are providing a custom URL resolver that matches everything and returns failure on open().
# This should prevent XXE attacks.

sub xml_match {
    my $uri = shift;
    print STDERR 'Attempted use of an external entity: (user: ' . $ENV{'REMOTE_USER'} . ', uri: ' . $uri . ")\n";
    return 1;
}

sub xml_open {
    return 0;
}

sub xml_read {
    return '';
}

sub xml_close {
    return;
}

1;
__END__

=head1 NAME

Cpanel::NetDAVServer - Provide a DAV Server

=head1 SYNOPSIS

    n/a

=head1 DESCRIPTION

This module provides a replacement for the get and put functions in
Net::DAV::Server along with others. These functions do not hold the files in memory like the original.

=head1 AUTHOR

cPanel, L.L.C.  <dev@cpanel.net>
Leon Brocard <acme@astray.com>

=head1 MAINTAINERS

cPanel, L.L.C.  <dev@cpanel.net>

=head1 COPYRIGHT

Copyright 2022 cPanel L.L.C. All rights reserved.

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
