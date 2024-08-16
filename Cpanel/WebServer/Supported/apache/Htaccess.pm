package Cpanel::WebServer::Supported::apache::Htaccess;

# cpanel - Cpanel/WebServer/Supported/apache/Htaccess.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::WebServer::Supported::apache::Htaccess

=head1 SYNOPSIS

    use Cpanel::ProgLang                                   ();
    use Cpanel::WebServer::Supported::apache::Handler  ();
    use Cpanel::WebServer::Supported::apache::Htaccess ();
    use Cpanel::WebServer::Userdata                    ();

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $lang_obj = $php->get_package( 'package' => 'ea-php54' );

    my $apache = Cpanel::WebServer->new()->get_server( 'type' => 'apache' );
    my $handler = Cpanel::WebServer::Supported::apache::Handler->new( 'type' => 'suphp', 'lang_obj' => $lang_obj, 'webserver' => $apache );

    my $userdata = Cpanel::WebServer::Userdata->new( 'user' => 'bob' );

    my $ht = Cpanel::WebServer::Supported::apache::Htaccess->new( 'userdata' => $userdata );
    eval { $ht->set_handler( 'vhost' => 'bob.com', 'package' => $package, 'handler' => $handler ); };

=head1 DESCRIPTION

We are using the .htaccess files in the document root of each virtual
host to set the version of any given language (PHP, Python, Ruby,
etc.) that will be in use for that virtual host.  We need to add a
handler/type line so that the appropriate version will be used.

The .htaccess file will contain a block such as the following once the
addition is made:

    # BEGIN cPanel-generated handler, do not edit
    <IfModule mime_module>
      # Use php54 as default
      AddHandler application/x-httpd-php54 .php
    </IfModule>
    # END cPanel-generated handler, do not edit

=cut

use strict;
use warnings;
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Exception                    ();
use Cpanel::Fcntl                        ();
use Cpanel::Quota::Temp                  ();
use Cpanel::Transaction::File::Raw       ();
use Cwd                                  ();

=pod

=head1 VARIABLES

A few variables to make our output more consistent, and ease looking
for that output, should we need to remove it.

=over 4

=item $BEGIN_TAG

The comment which starts out our "here is a cPanel handler" block.

=item $COMMENTS

A regular-expression snippet which maps to "one or more comment (#)
characters, with possible interspersed whitespace".  Just makes the
match expression easier to read.

=item $END_TAG

The comment which closes out a handler block.

=back

=cut

our $BEGIN_TAG = "BEGIN cPanel-generated handler, do not edit";
our $COMMENTS  = '\s*(?:\#\s*)*';
our $END_TAG   = "END cPanel-generated handler, do not edit";

=pod

=head1 METHODS

=head2 Cpanel::WebServer::Supported::apache::Htaccess-E<gt>new()

The constructor for creating a
Cpanel::WebServer::Supported::apache::Htaccess object.

=head3 Required argument keys

=over 4

=item userdata

A valid Cpanel::WebServer::Userdata object.

=back

=head3 Returns

A blessed reference to a
Cpanel::WebServer::Supported::apache::Htaccess object.

=head3 Dies

Throws a Cpanel::Exception object if any validation errors are
encountered.

=cut

sub new {
    my ( $class, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'userdata' ] ) unless defined $args{userdata};
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be an object of type “[_2]”.', [ 'userdata', 'Cpanel::WebServer::Userdata' ] ) unless eval { $args{userdata}->isa('Cpanel::WebServer::Userdata') };

    return bless( { userdata => $args{userdata} }, $class );
}

=pod

=head2 $htaccess-E<gt>set_handler()

Adds a PHP handler to the top of the .htaccess file at the document
root of a vhost, based on the passed-in package name.  Also strips all
other instances of handler comments and AddHandler or AddType
directives for PHP files.

If a new .htaccess file is created, it will be owned by the same user
which owns the document root of the domain.

The arguments are passed in as hash key-value pairs.

=head3 Required argument keys

=over 4

=item vhost

A scalar with the name of the domain to configure.

=item package

A scalar with the PHP package name to configure for the vhost.

=item handler

A Cpanel::WebServer::Supported::apache::Handler object.

=back

=head3 Returns

Nothing.

=head3 Dies

Throws a Cpanel::Exception object in the case of any argument
validation error or I/O error.

=cut

# NOTE: This method is here for internal usage, and is separated to make unit testing easier
sub _internal_set_handler {
    my ( $self, %args ) = @_;

    # TODO: validate that the handler arg is of the correct type.
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] )   unless defined $args{vhost};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] ) unless defined $args{package};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'handler' ] ) unless defined $args{handler};

    my $hnd = $args{handler}->get_htaccess_string(%args);
    if ($hnd) {
        my $docroot = $self->{userdata}->get_vhost_key( vhost => $args{vhost}, key => 'documentroot' );
        mkdir $docroot if ( !-e $docroot );
        my $fname    = $docroot . '/.htaccess';
        my $abs_path = Cwd::abs_path($fname);
        die Cpanel::Exception::create( 'IO::FileNotFound', [ path => $fname ] ) unless $abs_path;
        my $write_trans = Cpanel::Transaction::File::Raw->new( 'path' => $abs_path, 'permissions' => 0644, 'restore_original_permissions' => 1 );
        my $dataref     = $write_trans->get_data();

        my $lang     = $args{handler}->get_lang();
        my $type     = $lang->type();
        my $cleaned  = $self->_clean_htaccess_lines( $dataref, $lang );
        my $new_data = $$cleaned;

        $new_data .= "\n# $type -- $BEGIN_TAG\n";
        $new_data .= "$hnd\n";
        $new_data .= "# $type -- $END_TAG\n";

        $write_trans->set_data( \$new_data );
        $write_trans->save_and_close_or_die();
    }

    return 1;
}

sub set_handler {
    my ( $self, %args ) = @_;
    my $set_sub = sub { $self->_internal_set_handler(%args) };

    if ( $> == 0 ) {
        my $tempquota = Cpanel::Quota::Temp->new( user => $self->{userdata}->user() );
        $tempquota->disable();
        Cpanel::AccessIds::ReducedPrivileges::call_as_user( $set_sub, $self->{userdata}->id() );
        $tempquota->restore();
    }
    else {
        $set_sub->();
    }

    return 1;
}

=pod

=head2 $htacces-E<gt>unset_handler()

Removes the content-handler from a user's Apache htaccess file.

=cut

# NOTE: Much of this code is duplicated in
# Whostmgr::Transfers::SystemsBase::EA4::_strip_ea4_from_htaccess. If
# you update this code, please check if the same adjustment is
# necessary there.
sub _internal_unset_handler {
    my ( $self, %args ) = @_;

    for (qw( vhost lang )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $fname    = $self->{userdata}->get_vhost_key( vhost => $args{vhost}, key => 'documentroot' ) . '/.htaccess';
    my $abs_path = Cwd::abs_path($fname);
    die Cpanel::Exception::create( 'IO::FileNotFound', [ path => $fname ] ) unless $abs_path;
    my $result = sysopen my $fh, $abs_path, Cpanel::Fcntl::or_flags(qw( O_RDWR O_NOFOLLOW O_CREAT ));
    die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $fname, error => $!, mode => '+<' ] ) unless $result;

    my $htaccess;

    {
        local $/ = undef;
        $htaccess = <$fh>;
    }

    my $stripped = $self->_clean_htaccess_lines( \$htaccess, $args{lang} );
    seek( $fh, 0, 0 );
    print $fh $$stripped;

    # We don't want to die on a failed truncate, because
    # truncate may not be a valid operation if we're making a
    # new file.
    truncate( $fh, tell($fh) );

    close $fh
      or die Cpanel::Exception::create( 'IO::FileCloseError', [ path => $fname, error => $! ] );

    return 1;
}

sub unset_handler {
    my ( $self, %args ) = @_;
    my $unset_sub = sub { $self->_internal_unset_handler(%args) };

    if ( $> == 0 ) {
        my $tempquota = Cpanel::Quota::Temp->new( user => $self->{userdata}->user() );
        $tempquota->disable();
        Cpanel::AccessIds::ReducedPrivileges::call_as_user( $unset_sub, $self->{userdata}->id() );
        $tempquota->restore();
    }
    else {
        $unset_sub->();
    }

    return 1;

}

=pod

=head2 $htaccess-E<gt>_clean_htaccess_lines()

Private method to strip out lines which we've put into the file before.

=head3 Arguments

=over 4

=item $lines

An array ref containing the lines from the .htaccess file.

=item $lang

An object reference to a Cpanel::ProgLang::Supported::*

=back

=head3 Returns

The number of blocks that were stripped out of the file.

=head3 Notes

The challenge here is that we may have multiple blocks, each for a
different language.  They'll each have the language or package noted
within, but we only want to strip out the ones that are for the
language we're dealing with right now.  Unfortunately there's not a
super-clean way to grab only blocks which mention the language we're
dealing with, without potentially grabbing a ton of extra stuff.

We'll find each block in turn, and if it concerns our language, we'll
go ahead and strip it.  If it's for some other language, we'll save it
in a temporary array, and replace it when we've found all the blocks
that we recognize.

=cut

# NOTE: Much of this code is duplicated in
# Whostmgr::Transfers::SystemsBase::EA4::_strip_ea4_from_htaccess. If
# you update this code, please check if the same adjustment is
# necessary there.
sub _clean_htaccess_lines {
    my ( $self, $ref, $lang ) = @_;

    return unless ref $ref eq 'SCALAR';

    my $htaccess = $$ref;

    # Instead of trusting that there is only one instance, we'll
    # remove all instances we find.  We'll use non-greedy match (.*?)
    # between the begin and end lines, to grab as little as possible.

    my $type = $lang->type();

    while (
        $htaccess =~ m/($COMMENTS\#\s*$type\s*\-\-\s*\Q$BEGIN_TAG\E
                     .*?
                     \#\s*$type\s*\-\-\s*\Q$END_TAG\E)/isx
    ) {
        my $match = $1;

        # If our matched block has the language name, this is what
        # we're looking for.
        if ( $match =~ m/$type/sm ) {
            $htaccess =~ s/\Q$match\E//;
        }
    }

    return \$htaccess;
}

=pod

=head1 CONFIGURATION AND ENVIRONMENT

The module requires no configuration files or environment variables.

=head1 DEPENDENCIES

Cpanel::AccessIds::ReducedPrivileges, Cpanel::Exception,
Cpanel::Fcntl, and Cwd.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Handling .htaccess files located outside the document root would
require building a fake userdata object, or somehow coercing the
userdata to operate not at the docroot.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited

=cut

1;

__END__
