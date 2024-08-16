package Cpanel::ProgLang::Supported::php::Ini;

# cpanel - Cpanel/ProgLang/Supported/php/Ini.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding UTF-8

=head1 NAME

Cpanel::ProgLang::Supported::php::Ini

Note: All Cpanel::ProgLang namespaces and some attribute inconsistencies will change in ZC-1202. If you need to use Cpanel::ProgLang please note the specifics in ZC-1202 so the needful can be had.

=head1 SYNOPSIS

    use Cpanel::ProgLang ();

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ini = $php->get_ini( 'package' => 'ea-php54' );

    my $ini_path = $ini->get_system_ini();

    my $directives = $ini->get_valid_directive_info();

    my $bad_dirs = $ini->get_bad_directive_info();

    my $basic_dirs = $ini->get_basic_directive_info();

    my $file_basic_dirs = $ini->get_basic_php_directives_from_file();

    # System files
    my $basic = $ini->get_basic_directives();
    $ini->set_directives( 'directives' => { ... } );

    my $content = $ini->get_content();
    $ini->set_content( 'content' => $content );

    # User files
    my $path = '/home/bob/public_html';
    my $basic = get_basic_directives( 'path' => $path );
    $ini->set_directives( 'path' => $path, 'directives' => { ... } );

    my $content = $ini->get_content( 'path' => $path );
    $ini->set_content( 'content' => $content );

=head1 DESCRIPTION

This module is a language-specific module for PHP, which handles
operations on php.ini files in both system and user directories.

All public methods which take arguments expect them in hash key value
format.  Any missing required arguments will result in a
Cpanel::Exception.

=cut

use strict;
use warnings;
use Cpanel::Autodie                ();
use Cpanel::FileUtils::Copy        ();
use Cpanel::Exception              ();
use Cpanel::Transaction::File::Raw ();
use Cpanel::Version::Compare       ();
use Cpanel::LoadFile               ();
use Cwd                            ();
use Cpanel::ProgLang               ();
use Cpanel::SafeDir::MK            ();
use Cpanel::PHPINI                 ();
use Cpanel::Encoder::Tiny          ();
use File::Basename                 ();
use Try::Tiny;

=head1 VARIABLES

=over 4

=item @SYSTEM_SEARCH_PATH

The order and paths that are looked at when looking for a the system
PHP ini file.

=cut

our @SYSTEM_SEARCH_PATH = qw(
  /etc /etc/php.d /usr/local/lib /usr/local /usr/local/etc
);

our $SESSION_SAVE_PATH   = "/var/cpanel/php/sessions";
our $SESSION_MAXLIFETIME = "1440";

=item @BASIC_DIRECTIVES

The list of PHP directives which are commonly manipulated by customers
and have been deemed, "basic".

=cut

our @BASIC_DIRECTIVES = qw(
  allow_url_fopen allow_url_include asp_tags display_errors enable_dl
  file_uploads magic_quotes_gpc max_execution_time
  max_input_time max_input_vars memory_limit post_max_size register_globals safe_mode
  session.save_path session.gc_maxlifetime upload_max_filesize
  zlib.output_compression
);

# Within the PHP docu, memory values are listed as type integer, so
# our integer validation regexp here allows the K/M/G suffices.  See:
# http://php.net/manual/en/faq.using.php#faq.using.shorthandbytes
#
# Additionally, we'll parse the error-reporting-related keywords,
# because we unfortunately have to do it.  Keywords are:
#
# E_ERROR
# E_WARNING
# E_PARSE
# E_NOTICE
# E_CORE_ERROR
# E_CORE_WARNING
# E_COMPILE_ERROR
# E_COMPILE_WARNING
# E_USER_ERROR
# E_USER_WARNING
# E_USER_NOTICE
# E_STRICT
# E_RECOVERABLE_ERROR
# E_DEPRECATED
# E_USER_DEPRECATED
# E_ALL
#
# Any of these keywords can be preceded by a unary negation operator
# (~ or !).  The valid binary operators are &, |, and ^.  The spec
# doesn't mention whether parens are allowed in these expressions.

my $E_FLAG = '[~!]?\s*E_(?:(?:(?:CORE_|COMPILE_|USER_)?(?:ERROR|WARNING))|(?:USER_)?(?:NOTICE|DEPRECATED)|PARSE|STRICT|RECOVERABLE_ERROR|ALL)';
my $E_OPER = '[&|^]';

=item %TYPES

A structure which contains the data types which are supported by the
.ini parser, along with validation and conversion coderefs.

=back

=cut

our %TYPES = (
    'integer' => {
        'valid' => sub {
            return $_[0] =~ m/\A-?\d+[kmg]?\Z/i
              || $_[0]   =~ m/\A\s*$E_FLAG(?:\s*$E_OPER\s*$E_FLAG)*\Z/;
        },
        'convert' => sub { return $_[0] },
    },
    'float' => {
        'valid'   => sub { return $_[0] =~ m/\A-?\d+(?:\.\d*)?\Z/ },
        'convert' => sub { return $_[0] },
    },
    'string' => {
        'valid'   => sub { return $_[0] =~ m/\A[[:print:]]*\Z/ },
        'convert' => sub {
            my $lcstr = lc( $_[0] );
            if (   $lcstr eq 'none'
                || $lcstr eq 'null'
                || $lcstr eq 'off'
                || $lcstr eq 'no'
                || $lcstr eq 'false' ) {
                return qq{""};
            }
            elsif ($lcstr eq 'on'
                || $lcstr eq 'yes'
                || $lcstr eq 'true' ) {
                return qq{"1"};
            }
            elsif ( $_[0] =~ m/\A".*"\Z/ or $_[0] =~ m/\A'.*'\Z/ ) {
                return $_[0];
            }
            return qq{"$_[0]"};
        },
    },
    'boolean' => {
        'valid'   => sub { return $_[0] =~ m/\A(?:[01]|off|on|no|yes|false|true)\Z/i },
        'convert' => sub {
            my $lcstr = lc( $_[0] );
            if (   $lcstr eq '1'
                || $lcstr eq 'on'
                || $lcstr eq 'yes'
                || $lcstr eq 'true' ) {
                return 'On';
            }
            return 'Off';
        },
    },
);

=head1 METHODS

=head2 Cpanel::ProgLang::Supported::php::Ini-E<gt>new()

Create a new Ini object.

=head3 Required argument keys

=over 4

=item lang

The PHP lang object that we're using.

=item package

The package name of the PHP we wish to manage.

=back

=head3 Returns

A blessed hashref of type Cpanel::ProgLang::Supported::php::Ini.

=cut

sub new {
    my ( $class, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] )    unless defined $args{lang};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] ) unless defined $args{package};

    return bless(
        {
            lang     => $args{lang},
            package  => $args{package},
            lang_obj => $args{lang}->get_package( package => $args{package} ),
        },
        $class
    );
}

=head2 $ini-E<gt>get_system_ini()

Find the full path of the given ini file, or the main php.ini.  Each
file path is cached within the object, associated with its filename.

=head3 Optional arguments

=over 4

=item $filename

The filename of the ini file we wish to find.  If this argument is not
passed in, 'php.ini' will be used.

=back

=head3 Returns

The full pathname of the ini file in question.  Undef if the file does
not exist.

=head3 Notes

This method assumes we are operating within the framework of an
SCL-installed PHP package.  The I<lang_obj> returned by the I<lang>
object given to the constructor could somewhat alter the behaviour,
depending on its return from I<get_install_prefix()>.

=cut

sub get_system_ini {
    my ( $self, $ini_suffix ) = @_;
    $ini_suffix ||= 'php.ini';

    return $self->{$ini_suffix} if ( defined $self->{$ini_suffix} && -e $self->{$ini_suffix} );

    my $prefix = $self->{'lang_obj'}->get_install_prefix();

    my $did_loop_once = 0;
    my $ini_file;
  INI:
    for my $loc (@SYSTEM_SEARCH_PATH) {
        $ini_file = $prefix . $loc . '/' . $ini_suffix;
        last INI if -e $ini_file;
        $ini_file = undef;
    }

    if ( !$ini_file && !$did_loop_once ) {
        if ( -d $prefix . '/root' ) {
            $did_loop_once++;
            $prefix .= '/root';
            goto INI;
        }
    }
    $self->{$ini_suffix} = $ini_file if $ini_file;

    return $ini_file;
}

=head2 $ini-E<gt>get_default_system_ini()

This returns the path to the default php.ini regardless of its existence or not.

=head3 Notes

This method assumes we are operating within the framework of an
SCL-installed PHP package.  The I<lang_obj> returned by the I<lang>
object given to the constructor could somewhat alter the behaviour,
depending on its return from I<get_install_prefix()>.

=cut

sub get_default_system_ini {
    my ($self) = @_;
    return $self->{'lang_obj'}->get_install_prefix() . '/etc/php.ini';
}

=head2 $ini-E<gt>get_valid_directive_info()

Collects the list of valid directives for the version of PHP we're
handling.  The directives list will be cached within the object.

The file we use for the comprehensive list of directives is in the
phpini_directives.yaml file (and the “additional PHP INI directives” system)

=head3 Returns

A hashref which contains the directives, in the form:

    $directives = {
      'memory_limit => {
        'changeable' => 'PHP_INI_ALL',
        'default'    => '64M',
        'multiple'   => '0',
        'note'       => 'This sets the memory limit',
        'section'    => 'Core',
        'type'       => 'integer',
      },
      'enable_dl' => {
        'changeable' => 'PHP_INI_SYSTEM',
        'default'    => '1',
        'multiple'   => '0',
        'note'       => 'This sets the max input time',
        'section'    => 'Options & Information',
        'type'       => 'boolean',
      },
    }

=head3 Notes

The set returned by this method will be at most the same as the total
set of known directives, but may be smaller due to deprecations, new
directives in later versions, etc.

=cut

sub get_valid_directive_info {
    my ($self) = @_;
    my ( %good, %bad );

    return $self->{directives} if $self->{directives};

    # Remove directives which were added after our version, and
    # deprecated at or before our version and add them to a
    # 'bad_directives' hash.
    my $dirs    = Cpanel::PHPINI::get_directives_from_filesys();
    my $version = $self->{'lang_obj'}->get_version();

    while ( my ( $dir, $href ) = each(%$dirs) ) {
        if (   ( defined $href->{added} && Cpanel::Version::Compare::compare( $version, '<', $href->{added} ) )
            || ( defined $href->{deprecated} && Cpanel::Version::Compare::compare( $version, '>=', $href->{deprecated} ) ) ) {
            $bad{$dir} = $href;
        }
        $good{$dir} = $href unless exists $bad{$dir};
    }

    $self->{bad_directives} = \%bad;
    $self->{directives}     = \%good;

    return \%good;
}

=head2 $ini-E<gt>get_bad_directive_info()

Retrieves a hash reference of directives that were found in the
cPanel-supplied phpini_directives.yaml file (and the “additional PHP INI directives” system),
but are either deprecated or have not been implemented yet in the specified version.

The directives list will be cached within the object.

=head3 Returns

A hashref containing the directives similar in form to
I<get_valid_directive_info()>.

=cut

sub get_bad_directive_info {
    my $self = shift;

    # initialize the good and bad directives
    $self->get_valid_directive_info();
    return $self->{bad_directives};
}

=head2 $ini-E<gt>get_basic_directive_info()

Returns a hash reference of basic valid directives found within a
system (or explicitly defined) PHP ini file.  The basic list
was compiled together by querying our existing user base for
frequently changed directives.

The basic directive list will be a subset of valid directives.
Additionally, basic and bad directives should be mutually exclusive.

The directives list will be cached within the object.

=head3 Returns

A hashref containing the directives similar in form to
I<get_valid_directive_info()>.

=cut

sub get_basic_directive_info {
    my ($self) = @_;

    return $self->{basic_directives} if $self->{basic_directives};

    my $valid = $self->get_valid_directive_info();
    my %basic = map { $_ => $valid->{$_} } grep { exists $valid->{$_} } @BASIC_DIRECTIVES;
    $self->{basic_directives} = \%basic;

    #determine the correct session.save_path
    $basic{'session.save_path'}{cpanel_default} .= "/$self->{package}"
      if exists $basic{'session.save_path'}{cpanel_default};

    return \%basic;
}

=head2 $ini-E<gt>get_basic_php_directives_from_file()

Retrieves the basic directives from a file on disk.

=head3 Required argument keys

=over 4

=item path

The pathname of the file we wish to read.

=back

=head3 Optional argument keys

=over 4

=item all

If this argument is set, all php directives in the target file
are returned. Non-basic directives will only have a key and value.
They will not have a default value or note.

=back

=head3 Returns

A hashref containing the directives similar in form to
I<get_valid_directive_info()>.

=head3 Dies

Any I/O failures will result in a Cpanel::Exception.

=head3 Notes

Since this is strictly a read operation, there is no need for file
locking.

=cut

sub get_basic_php_directives_from_file {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'path' ] ) unless defined $args{path};

    my $path = Cwd::abs_path( $args{path} );
    my %directives;

    # We don't need to lock (safeopen, etc.) for just reading.  Plain
    # open will be fine.
    my $contents;
    return {} unless ( $contents = Cpanel::LoadFile::loadfile($path) );

    my $basic = $self->get_basic_directive_info();    # use this to filter out only the basic directives below
    foreach my $line ( split( m{\n}, $contents ) ) {
        if ( $line =~ m/\A\s*(\S+)\s*=\s*(.*)\Z/ ) {
            my ( $key, $value ) = ( $1, $2 );
            my $dir = $basic->{$key};

            if ( defined($dir) && defined( $dir->{type} ) && ( $dir->{type} eq 'string' ) ) {
                $value =~ s/\s+\z//;
            }
            else {
                $value =~ s/\s*(?:;.*)?$//;
            }
            if ( !$dir ) {

                # Gather up all the non-basic directives, if we want them.
                if ( $args{'all'} ) {
                    $directives{$key} = { key => $key, value => $value };
                }
                next;
            }

            $value =~ s/\A"|"\z//g;

            $directives{$key} = {
                key           => $key,
                value         => $value,
                type          => $dir->{type},
                default_value => $dir->{default},
                info          => $dir->{note},
                php_ini_mode  => $dir->{changeable},
            };
            $directives{$key}{cpanel_default} = $dir->{cpanel_default}
              if exists $dir->{cpanel_default};
        }
    }

    return \%directives;
}

=head2 $ini-E<gt>get_basic_directives()

Returns an array reference of basic valid directives found within a
system (or explicitly defined) PHP ini file.  The basic list
was compiled together by querying our existing user base for
frequently changed directives.  The difference between
this method and get_basic_directives() is that this one takes into
account inheritance.

If a basic directive is left unspecified in the system or defined
path, the default value is retrieved from the cPanel-supplied
phpini_directives.yaml file (and the “additional PHP INI directives” system).

The directive values are checked in the following order:
 - user defined (defined in user's php.ini file)
 - system defined (supplied by PHP package)
 - php defined (phpini_directives.yaml file (and the “additional PHP INI directives” system)

The directives list will be cached within the object.

=head3 Optional argument keys

=over 4

=item path

An optional pathname of a php.ini file.  Without this argument, the system locations will be searched.

=back

=head3 Returns

An arrayref of directives, of the form:

    $directives = [
      {
        'key'           => 'memory_limit',
        'value'         => '123M',
        'type'          => 'integer',
        'info'          => 'This sets the memory limit',
        'default_value' => '64M',
        'php_ini_mode' => 'PHP_INI_ALL',
      },
      {
        'key'           => 'max_input_time',
        'value'         => '30',
        'type'          => 'integer',
        'info'          => 'This sets the max input time',
        'default_value' => '30',
        'php_ini_mode'  => 'PHP_INI_PERDIR',
      },
    ]

=cut

sub get_basic_directives {
    my ( $self, %args ) = @_;

    # Grab the system-defined PHP directives
    my $path = $self->get_system_ini();
    die Cpanel::Exception::create( 'IO::FileNotFound', [ 'path' => 'php.ini' ] ) unless $path;
    my $dirs = $self->get_basic_php_directives_from_file( 'path' => $path, 'all' => $args{'all'} );

    # Grab user's changes to the same directives, if any
    if ( defined $args{'path'} ) {
        my $user = $self->get_basic_php_directives_from_file( 'path' => $args{'path'}, 'all' => $args{'all'} );

        # Shallow merge the two hashes
        while ( my ( $key, $href ) = each(%$user) ) {
            $dirs->{$key} = $href;
        }
    }

    # set default values if the system or user haven't done so
    my $basic = $self->get_basic_directive_info();

    for my $key ( keys %$basic ) {
        unless ( exists $dirs->{$key} ) {
            my $dir = $basic->{$key};
            $dirs->{$key} = {
                'key'           => $key,
                'value'         => $dir->{'default'},
                'type'          => $dir->{'type'},
                'default_value' => $dir->{'default'},
                'info'          => $dir->{'note'},
                'php_ini_mode'  => $dir->{'changeable'},
            };
            $dirs->{$key}{cpanel_default} = $dir->{cpanel_default}
              if exists $dir->{cpanel_default};
        }
    }

    return [ sort { $a->{'key'} cmp $b->{'key'} } values %$dirs ];
}

=head2 $ini-E<gt>set_directives()

Method to save the structured directives to the php.ini file.

=head3 Required argument keys

=over 4

=item directives

A directives hashref will contain the PHP settings in this form:

    $hashref = {
      'memory_limit'   => '123M',
      'max_input_time' => '30',
    }

=back

=head3 Optional argument keys

=over 4

=item path

A string referencing a specific (alternate) path to save directives
into.  The default save path is the system php.ini.

=item userfiles

A boolean to create the .user.ini and .htaccess (with just the settings that can be changed via the given
file per L<http://php.net/manual/en/configuration.changes.modes.php>). Default is to not do it.

If one of the files already exists and is a symlink it will be moved to <file>.<time>.<unique>.bak.

Why would you need those?

The php.ini in a user's home directory is overridden by EA4's php.d directory.
Creating the user-ini file will ensure it overrides default settings.

The .htaccess allows sites switched to DSO the best chance of working the same as it did before.

=back

=head3 Returns

Nothing.

=head3 Dies

Any I/O failure while saving will result in a Cpanel::Exception.

=cut

sub set_directives {
    my ( $self, %args ) = @_;
    my ( $read_path, $write_path );

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'directives' ] ) unless defined $args{'directives'};

    my %directives = %{ $args{'directives'} };    # don't modify user's input

    $self->_validate_directives( \%directives );

    if ( defined $args{'path'} ) {

        # If the file doesn't exist, we return normal directives as if it does.
        $read_path = $write_path = $args{'path'};
    }
    else {
        # We bail out completely if we can't open the system php ini file
        $read_path = $self->get_system_ini();
        die Cpanel::Exception::create( 'IO::FileNotFound', [ 'path' => 'php.ini' ] ) unless $read_path;
        $write_path = $read_path || $self->get_default_system_ini();
    }

    my $lines_ar = $self->_get_updated_directive_lines( $read_path, \%directives );

    # Add remaining directives that weren't already in the user's php.ini file
    for my $key ( sort keys %directives ) {
        my $value = $self->_convert_directive( $key, $directives{$key} );
        push @{$lines_ar}, "$key = $value\n";
    }

    $self->_write_configs( $write_path, $lines_ar, %args );

    return 1;
}

=head2 $ini-E<gt>get_content()

Retrieve the full-text contents of a PHP ini file.  If you do not
supply the optional path, it will retrieve the contents of the system
PHP ini.  However, if you supply an explicit path, then it will return
that instead.

=head3 Optional argument keys

=over 4

=item path

The pathname of a php.ini file.  If no path is specified, the system
paths will be used.

=back

=head3 Returns

A reference to the file contents (string).

=head3 Notes

If an explicit path is supplied and the file cannot be opened, an
empty string will be returned.  This is to ensure compatibility with
user ini files since they often won't exist.  In contrast, if you do
not specify a path (which means you'll be accessing the system PHP),
then a Cpanel::Exception will be thrown.

=cut

sub get_content {
    my ( $self, %args ) = @_;
    my $path = defined $args{path} ? $args{path} : $self->get_system_ini();
    my $content;

    if ( defined $path && open( my $fh, '<', $path ) ) {
        local $/;
        $content = <$fh>;
        close $fh or die Cpanel::Exception::create( 'IO::FileCloseError', [ path => $path, error => $! ] );
    }
    else {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ mode => '<', path => $path, error => $! ] ) unless defined $args{path};
        $content = '';
    }

    return \$content;
}

=head2 $ini-E<gt>set_content()

Save a full-text string into the php.ini file.

=head3 Required argument keys

=over 4

=item content

The reference to a full-text string which should be saved to the php.ini file.

=back

=head3 Optional argument keys

=over 4

=item path

An optional path to a php.ini file.  If no path is specified, the
system paths will be used.

=item userfiles

A boolean to create the .user.ini and .htaccess (with just the settings that can be changed via the given
file per L<http://php.net/manual/en/configuration.changes.modes.php>). Default is to not do it.

If one of the files already exists and is a symlink it will be moved to <file>.<time>.<unique>.bak.

Why would you need those?

The php.ini in a user's home directory is overridden by EA4's php.d directory.
Creating the user-ini file will ensure it overrides default settings.

The .htaccess allows sites switched to DSO the best chance of working the same as it did before.

=back

=head3 Returns

Nothing.

=head3 Dies

Any I/O errors will result in a Cpanel::Exception.

=cut

sub set_content {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'content' ] ) unless defined $args{content};

    my $content_sr = $args{content};

    my $path = defined $args{path} ? $args{path} : ( $self->get_system_ini() || $self->get_default_system_ini() );

    $self->_validate_content($content_sr);

    $self->_write_configs( $path, [ map { "$_\n" } split( /\n/, ${$content_sr} ) ], %args );

    return 1;
}

=head1 PRIVATE METHODS

=head2 $ini-E<gt>_validate_directives()

Validates the supplied directives, for form and format.

=head3 Arguments

=over 4

=item $directives

A hashref which contains the desired settings, of the form:

    $args_hashref = {
      'memory_limit'   => '123M',
      'max_input_time' => '30',
    }

=back

=head3 Returns

Nothing.  Completion implies valid input.

=head3 Dies

Any invalid parameter will result in a Cpanel::Exception.  Conditions
which are checked include:

=over 4

=item *

No directives

=item *

Invalid directive keys

=item *

Directives which are not valid for the package

=item *

Directives which may take multiple values

=item *

Values which do not pass type checking

=back

=cut

sub _validate_directives {
    my ( $self, $directives ) = @_;
    my $valid = $self->get_valid_directive_info();
    my $bad   = $self->get_bad_directive_info();

    # # Bad argument type, or empty directive hashref
    die Cpanel::Exception::create( 'InvalidParameter', 'You must specify one or more [asis,PHP] directives.' ) unless keys %$directives;

    my @exceptions = ();
    for my $key ( keys %$directives ) {

        # Garbage keys
        unless ( $key =~ m/\A[._A-Za-z0-9]+\Z/ ) {
            push @exceptions, Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,PHP] directive.', [ Cpanel::Encoder::Tiny::safe_html_encode_str($key) ] );
            next;
        }

        # Deprecated or not-yet-added keys
        if ( exists $bad->{$key} ) {
            push @exceptions, Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid directive for [asis,PHP] version “[_2]”.', [ $key, $self->{lang_obj}->get_version() ] );
            next;
        }

        if ( exists $valid->{$key} ) {

            # We don't support multi-valued directives
            if ( $valid->{$key}{'multiple'} ) {
                push @exceptions, Cpanel::Exception::create( 'InvalidParameter', 'The [asis,PHP] directive “[_1]” is not supported by this interface.', [$key] );
                next;
            }

            # The value isn't formatted reasonably
            if ( $valid->{$key}{'type'} ) {
                unless ( $TYPES{ $valid->{$key}{'type'} }{'valid'}->( $directives->{$key} ) ) {
                    push @exceptions, Cpanel::Exception::create( 'InvalidParameter', 'The [asis,PHP] directive “[_1]” is not formatted correctly: “[_2]”.', [ $key, Cpanel::Encoder::Tiny::safe_html_encode_str( $directives->{$key} ) ] );
                    next;
                }
            }
        }
    }
    die Cpanel::Exception::create( 'Collection', [ 'exceptions' => \@exceptions ] ) if @exceptions;

    return 1;
}

my $cpanel_edit_section_name  = 'cPanel-generated php ini directives, do not edit';
my @cpanel_edit_section_lines = (
    'Manual editing of this file may result in unexpected behavior.',
    'To make changes to this file, use the cPanel MultiPHP INI Editor (Home >> Software >> MultiPHP INI Editor)',
    'For more information, read our documentation (https://go.cpanel.net/EA4ModifyINI)',
);
my $ini_comment_block = "; $cpanel_edit_section_name\n";
for my $text (@cpanel_edit_section_lines) {
    $ini_comment_block .= "; $text\n";
}
$ini_comment_block .= "\n";

sub _write_configs {
    my ( $self, $ini_path, $lines_ar, %args ) = @_;

    ####
    ## This would be better done via a multi-file capable Cpanel::Transaction type thing
    ##  but for now it is what it is since we don't have such a command pattern module
    ##   and making one is waaaay out of scope for this iteration :(
    ####

    my $bu_ext = time() . ".$$.orig";
    my $orig   = "$ini_path.$bu_ext";
    my ( $uid, $gid ) = ( stat($ini_path) )[ 4, 5 ];
    $uid ||= 0;
    $gid ||= 0;
    _make_backup_or_die( $ini_path, $orig );

    try {
        my $write_trans;
        if ( -e $ini_path ) {
            $write_trans = Cpanel::Transaction::File::Raw->new( 'ownership' => [ $uid, $gid ], 'path' => $ini_path, 'permissions' => 0644, restore_original_permissions => 1 );
        }
        else {
            $write_trans = Cpanel::Transaction::File::Raw->new( 'path' => $ini_path, 'permissions' => 0644, restore_original_permissions => 1 );
        }
        if ( !grep { m/; \Q$cpanel_edit_section_name\E/ } @{$lines_ar} ) {
            unshift @{$lines_ar}, $ini_comment_block;
        }
        $write_trans->set_data( \join( '', @{$lines_ar} ) );
        $write_trans->save_and_close_or_die();
    }
    catch {
        my $err = $_;
        _rollback_then_die( $err, $orig, $ini_path );
    };

    if ( $args{userfiles} ) {
        try {
            my @userini_lines = @{$lines_ar};
            if ( !grep { m/; \Q$cpanel_edit_section_name\E/ } @userini_lines ) {
                unshift @userini_lines, $ini_comment_block;
            }

            my $userini = $self->_write_userini( $ini_path, \@userini_lines, { bu_ext => $bu_ext, keep_orig => 1 } );
            try {
                my @htaccess_lines = @{$lines_ar};
                $self->_write_htaccess( $ini_path, \@htaccess_lines, { bu_ext => $bu_ext } );
                unlink "$userini.$bu_ext";    # now that we are done we can clean up our keep_orig since we won't be rolling it back at this point
            }
            catch {
                my $err = $_;
                if ( -f "$userini.$bu_ext" ) {
                    _rollback_then_die( $err, "$userini.$bu_ext", $userini );
                }
                else {
                    die $err;
                }
            }
        }
        catch {
            my $err = $_;
            _rollback_then_die( $err, $orig, $ini_path );
        };
    }

    if ( -f $orig ) {
        unlink($orig) || warn "Could not unlink “$orig”: $!\n";    # success, cleanup “rollback” file
    }

    return 1;
}

sub _rollback_then_die {
    my ( $err, $orig, $ini_path ) = @_;

    try {
        if ( -l $orig || -f _ ) {
            Cpanel::Autodie::rename( $orig, $ini_path );    # failure, rollback $ini_path …
        }
        die $err;                                           # … and rethrow error
    }
    catch {
        my $err2 = $_;
        $err .= "\n"    if substr( $err, -1 ) ne "\n";
        die "$err$err2" if $err ne $err2;
        die $err2;
    };

    return 1;
}

sub _make_backup_or_die {
    my ( $ini_path, $orig ) = @_;

    if ( -l $ini_path || -f _ ) {
        if ( -l _ ) {    # we need to remove symlinks instead of copying them because then we'll be writing the target whcih might be bad (e.g. /opt/…). Also safecopy() barfs on broken symlinks.
            unlink $orig;
            my $target = readlink($ini_path);
            symlink( $target, $orig ) or die Cpanel::Exception::create( 'IO::SymlinkCreateError', [ error => $!, oldpath => $target, newpath => $orig ] );
            unlink $ini_path;
        }
        elsif ( -o _ ) {    # the copy will be owned by $> and, if restored, owned by $> not the current owner. If we use rename() instead then there will be a brief period wher theri settings will not be in effect whcih is even worse. This way, minor race condition aside, we avoid both problems.
            if ( !Cpanel::FileUtils::Copy::safecopy( $ini_path, $orig ) ) {
                die Cpanel::Exception::create(
                    'IO::FileCopyError',
                    [
                        'source'      => $ini_path,
                        'destination' => $orig,
                        'error'       => $!,
                    ]
                );
            }
        }
        else {
            die Cpanel::Exception::create( 'IO::EUIDMismatch', [ path => $ini_path ] );
        }
    }

    return 1;
}

sub _filter_ini_directives {
    my ( $self, $data_ref, @modes ) = @_;

    my $pipe_delimited = join( "|", map { quotemeta($_) } @modes );
    die "No modes given to _filter_ini_directives()\n" if !$pipe_delimited;

    my $valid_directives = $self->get_valid_directive_info();
    my %keep             = map { defined $valid_directives->{$_}{'changeable'} && $valid_directives->{$_}{'changeable'} =~ m{^(?:$pipe_delimited)$} ? ( $_ => 1 ) : () } keys %{$valid_directives};

    my %removed;

    # De-construct $data_ref
    my $type = ref($data_ref);
    my @directive_lines;
    my @new_directive_lines;
    if ( $type eq 'SCALAR' ) {
        @directive_lines = map { "$_\n" } split( /\n/, ${$data_ref} );
    }
    elsif ( $type eq 'ARRAY' ) {
        @directive_lines = @{$data_ref};
    }
    else {
        die "_filter_ini_directives() only takes SCALAR or ARRAY refs\n";
    }

    # Filter data
    for my $line (@directive_lines) {
        if ( $line =~ m/^\s*(\S+)?\s*=\s*([^;].*)\s*$/ ) {
            my ( $key, $val ) = ( $1, $2 );
            if ( $key =~ m/\;/ ) {
                push @new_directive_lines, $line;    # comment or non-dorective line, just pass it through as is
                next;
            }
            chomp($val);
            $val =~ s/ +$//;

            if ( defined( $valid_directives->{$key} ) && defined( $valid_directives->{$key}{'type'} ) && defined( $TYPES{ $valid_directives->{$key}{'type'} } ) && $valid_directives->{$key}{'type'} ne 'string' ) {
                $val =~ s/\s*\;.*$//;
            }

            if ( exists $keep{$key} ) {
                my $value = $self->_convert_directive( $key, $val );
                push @new_directive_lines, "$key = $value\n";
            }
            else {
                $removed{$key} = $val;
            }
        }
        else {
            push @new_directive_lines, $line;    # comment or non-dorective line, just pass it through as is
        }
    }

    # Re-construct $data_ref
    if ( $type eq 'SCALAR' ) {
        ${$data_ref} = join( "", @new_directive_lines );
    }
    else {    # we've already died if it was not a supported reference
        @{$data_ref} = @new_directive_lines;
    }

    return \%removed;    # in case anyone ever cares
}

sub _write_htaccess {    ## no critic qw(ProhibitExcessComplexity) – patches welcome!
    my ( $self, $ini_path, $content_ar, $opts ) = @_;
    my @valid_directive_modes = qw(PHP_INI_PERDIR PHP_INI_ALL);

    my $write_dir = ( !-l $ini_path && -d _ ) ? $ini_path : File::Basename::dirname($ini_path);
    my $htaccess  = "$write_dir/.htaccess";

    $opts->{bu_ext} ||= time() . ".$$.bak";
    my $orig = "$htaccess.$opts->{bu_ext}";
    _make_backup_or_die( $htaccess, $orig );

    my $major_version = substr( $self->{'lang_obj'}->get_version(), 0, 1 ) || 5;
    $self->_filter_ini_directives( $content_ar, @valid_directive_modes );

    try {
        my $write_trans  = Cpanel::Transaction::File::Raw->new( 'path' => $htaccess, 'permissions' => 0644, 'restore_original_permissions' => 1 );
        my $dataref      = $write_trans->get_data();
        my $cleaned_data = '';                                                                                                                       # $dataref w/out any of our commented sections

        if ( $dataref && ${$dataref} ) {
            my $current_php_value = "";

            my $in_chunk = 0;
            my $in_ifmod = 0;
            for my $line ( split( /\n/, ${$dataref} ) ) {
                if ( !$in_chunk ) {
                    if ( $line =~ m/^# BEGIN \Q$cpanel_edit_section_name\E$/ ) {
                        $in_chunk = 1;
                        $in_ifmod = 0;
                    }
                    else {
                        $cleaned_data .= "$line\n";
                    }
                }
                else {
                    if ( $line =~ m/^# END \Q$cpanel_edit_section_name\E$/ ) {
                        $in_chunk = 0;
                        $in_ifmod = 0;
                    }
                    else {
                        if ( $line =~ m/^\s*<IfModule php\Q$major_version\E_module>/ ) {
                            $in_ifmod = 1;
                        }
                        elsif ( $in_ifmod && $line =~ m{^\s*</IfModule>} ) {
                            $in_ifmod = 0;
                        }
                        elsif ($in_ifmod) {
                            chomp($line);
                            if ( length($line) && $line !~ m/^\s*#/ ) {
                                $line =~ s/\s*#.*//;

                                # normalize "php_value|php_flag $key $value" to "$key = $value"
                                if ( $line =~ m/php_(?:value|flag)\s+(\S)\s+(.*)\s*$/ ) {
                                    my ( $key, $value ) = ( $1, $2 );
                                    $value =~ s/\s*\;.*//;
                                    $current_php_value .= "$key = $value\n";
                                }    # else: ignore it
                            }
                        }    # else: ignore it
                    }
                }
            }
            if ($current_php_value) {

                # Update $content_ar w/ $current_php_value, preferring new values in $content_ar
                if ( !-e "/usr/local/bin/ea_convert_php_ini" ) {    # This madness will go away with EA-5696
                    warn "Unable to preserve current values in “$htaccess” without the ea-cpanel-tools package installed.\n";
                }
                else {
                    $self->_filter_ini_directives( \$current_php_value, @valid_directive_modes );

                    require "/usr/local/bin/ea_convert_php_ini";    ##no critic (RequireBarewordIncludes) This madness will go away with EA-5696
                    my $parser  = Parse::PHP::Ini->new;
                    my $ltree   = $parser->parse( str => \$current_php_value );
                    my $rtree   = $parser->parse( str => \join( '', @{$content_ar} ) );
                    my $mtree   = $parser->merge( $ltree, $rtree );
                    my $cont_sr = $parser->render($mtree);
                    @{$content_ar} = map { "$_\n" } split( /\n/, ${$cont_sr} );
                    shift @{$content_ar};                           # [PHP] section header
                    $self->_filter_ini_directives( $content_ar, @valid_directive_modes );
                }
            }
        }

        $cleaned_data =~ s/[\n]+$//;
        $cleaned_data .= "\n" if length($cleaned_data);

        # based on $content_ar: change "$key = $value" lines to "php_value|php_flag $key $value"
        my $valid_directives = $self->get_valid_directive_info();
        my $new_content      = join(
            '',
            map {
                my $l = $_;
                my ( $k, $v ) = split( /\s*=\s*/, $l, 2 );
                $v ||= '';
                $v =~ s/[\n]+$//;
                my $php_type    = defined $valid_directives->{$k}{type} && $valid_directives->{$k}{type} eq 'boolean' ? "php_flag" : "php_value";
                my $empty_value = !defined $v || !length($v) || $v eq '""' || $v eq "''" || $k =~ ";"                 ? 1          : 0;
                $empty_value ? () : ("   $php_type $k $v\n")
            } @{$content_ar}
        );
        $new_content .= "\n" if substr( $new_content, -1, 1 ) ne "\n";

        my $major_version = substr( $self->{'lang_obj'}->get_version(), 0, 1 ) || 5;

        # Ifmodule php7_module or php5_module
        $cleaned_data .= "\n# BEGIN $cpanel_edit_section_name\n";
        for my $text (@cpanel_edit_section_lines) {
            $cleaned_data .= "# $text\n";
        }
        $cleaned_data .= "<IfModule php${major_version}_module>\n$new_content</IfModule>\n";
        $cleaned_data .= "<IfModule lsapi_module>\n$new_content</IfModule>\n";
        $cleaned_data .= "# END $cpanel_edit_section_name\n";

        $write_trans->set_data( \$cleaned_data );
        $write_trans->save_and_close_or_die();
    }
    catch {
        my $err = $_;
        _rollback_then_die( $err, $orig, $htaccess );
    };

    if ( -f $orig ) {
        unlink($orig) || warn "Could not unlink “$orig”: $!\n";    # success, cleanup “rollback” file
    }

    return 1;
}

sub _write_userini {
    my ( $self, $ini_path, $content_ar, $opts ) = @_;
    my @valid_directive_modes = qw(PHP_INI_USER PHP_INI_PERDIR PHP_INI_ALL);

    my $write_dir = ( !-l $ini_path && -d _ ) ? $ini_path : File::Basename::dirname($ini_path);
    my $userini   = "$write_dir/.user.ini";

    $opts->{bu_ext} ||= time() . ".$$.bak";
    my $orig = "$userini.$opts->{bu_ext}";
    _make_backup_or_die( $userini, $orig );

    $self->_filter_ini_directives( $content_ar, @valid_directive_modes );

    try {
        my $write_trans = Cpanel::Transaction::File::Raw->new( 'path' => $userini, 'permissions' => 0644, restore_original_permissions => 1 );

        my $dataref = $write_trans->get_data();
        if ( $dataref && ${$dataref} ) {
            if ( !-e "/usr/local/bin/ea_convert_php_ini" ) {    # This madness will go away with EA-5696
                warn "Unable to preserve current values in “$userini” without the ea-cpanel-tools package installed.\n";
                if ( !grep { m/; \Q$cpanel_edit_section_name\E/ } @{$content_ar} ) {
                    unshift @{$content_ar}, $ini_comment_block;
                }
                $write_trans->set_data( \join( '', @{$content_ar} ) );
            }
            else {
                $self->_filter_ini_directives( $dataref, @valid_directive_modes );

                require "/usr/local/bin/ea_convert_php_ini";    ##no critic (RequireBarewordIncludes) This madness will go away with EA-5696
                my $parser  = Parse::PHP::Ini->new;
                my $ltree   = $parser->parse( str => $dataref );
                my $rtree   = $parser->parse( str => \join( '', @{$content_ar} ) );
                my $mtree   = $parser->merge( $ltree, $rtree );
                my $cont_sr = $parser->render($mtree);
                if ( ${$cont_sr} !~ m/; \Q$cpanel_edit_section_name\E/ ) {
                    ${$cont_sr} = $ini_comment_block . ${$cont_sr};
                }

                $write_trans->set_data($cont_sr);
            }
        }
        else {
            if ( !grep { m/; \Q$cpanel_edit_section_name\E/ } @{$content_ar} ) {
                unshift @{$content_ar}, $ini_comment_block;
            }
            $write_trans->set_data( \join( '', @{$content_ar} ) );
        }

        $write_trans->save_and_close_or_die();
    }
    catch {
        my $err = $_;
        _rollback_then_die( $err, $orig, $userini );
    };

    if ( !$opts->{keep_orig} && -f $orig ) {
        unlink($orig) || warn "Could not unlink “$orig”: $!\n";    # success, cleanup “rollback” file
    }

    return $userini;
}

=head2 $ini-E<gt>_convert_directive()

Format a directive for output to a file.  The conversion routines are
contained within the I<%TYPES> variable.

=head3 Arguments

=over 4

=item $key

The name of the directive.

=item $value

The value for the directive.

=back

=head3 Returns

The formatted value.  If the directive is not recognized, no
formatting will be done, and the value will be returned as-is.

=cut

sub _convert_directive {
    my ( $self, $key, $value ) = @_;
    $value =~ s/\s+\z//;

    my $dir = $self->get_valid_directive_info();

    if ( exists $dir->{$key} && exists $dir->{$key}{'type'} ) {
        return $TYPES{ $dir->{$key}{'type'} }{'convert'}->($value);
    }
    return $value;
}

=head2 $ini-E<gt>_get_updated_directive_lines()

Reads a php.ini file, and substitutes the supplied directives in the
appropriate places in the .ini content.

=head3 Arguments

=over 4

=item $path

The pathname of the file to read.

=item $directives

The set of directives to insert.

=back

=head3 Returns

An array ref of the lines from the supplied file.

=head3 Dies

If the file exists but can not be opened, a Cpanel::Exception will
result.

=head3 Notes

A non-existent file or an empty one will result in contents of just
the directives that were supplied.

All lines, commented or not, which reference a directive in the input
set will be removed, and replaced in the first instance of the line,
with the new value.

Any non-recognized directives will be inserted at the end of the file.

=cut

sub _get_updated_directive_lines {
    my ( $self, $path, $directives ) = @_;
    $directives ||= {};
    my @lines = ();
    my %done  = ();

    my $write_trans = Cpanel::Transaction::File::Raw->new( 'path' => $path, 'permissions' => 0644, restore_original_permissions => 1 );
    my $dataref     = $write_trans->get_data();

    # The first line we encounter which has the directive we want,
    # commented or not, we'll uncomment it and modify the value.  Any
    # subsequent lines with the same directive, we'll just ignore
    # them, and remove them from the output.
  LINE:
    foreach my $line ( split( m{\n}, $$dataref ) ) {
        $line = "$line\n";
        if ( $line =~ m/\A[;\s]*(\S+)\s*=\s*.*\Z/ ) {
            my $key = $1;

            # Throw this line away if we've already processed this directive
            next LINE if exists $done{$key};

            # Keep this line if we have no updates for this directive
            push @lines, $line and next LINE unless exists $directives->{$key};

            # Actually make the update
            my $value = $self->_convert_directive( $key, $directives->{$key} );
            $line = "$key = $value\n";

            # Make sure we don't process this directive again
            $done{$key} = delete $directives->{$key};
        }
        push @lines, $line;
    }
    $write_trans->close_or_die();
    return \@lines;
}

=head2 B<_validate_content($content)>

Validates the supplied content.  A less-stringent version of
I<_validate_directives()>.

=head3 Arguments

=over 4

=item $content

A scalar which contains the full text of a php.ini file.

=back

=head3 Returns

Nothing.  Completion implies valid input.

=head3 Dies

Any validation failure will result in a Cpanel::Exception.  Failure
cases include:

=over 4

=item *

Empty input content

=item *

A line that isn't a directive, blank line, comment, or section header

=item *

The content doesn't apparently contain any directives

=back

=cut

sub _validate_content {
    my ( $self, $content ) = @_;

    die Cpanel::Exception::create( 'InvalidParameter', 'The [asis,php.ini] file is empty.' )
      unless $$content ne '';

    my %directives = ();
    my @exceptions = ();
  LINE:
    for my $line ( split /\n/, $$content ) {
        if ( $line =~ m/\A\s*\[[^]]+\]/ or $line =~ m/\A\s*;/ or $line =~ m/\A\s*\Z/ ) {

            # section header, comment, or blank line:  no-op
            next LINE;
        }
        elsif ( $line =~ m/\A\s*(\S+)\s*=\s*(.*)\Z/ ) {
            $directives{$1} = $2;
        }
        else {
            push @exceptions, Cpanel::Exception::create( 'InvalidParameter', 'The [asis,php.ini] file contains an invalid line: “[_1]”.', [$line] );
        }
    }
    die Cpanel::Exception::create( 'Collection',       [ 'exceptions' => \@exceptions ] ) if @exceptions;
    die Cpanel::Exception::create( 'InvalidParameter', 'The [asis,php.ini] file does not contain any directives.' )
      unless keys %directives;

    return 1;
}

=head2 B<setup_session_save_path($path)>

PHP's default session save path is /tmp. This has some serious security implications,
so we want to save the session files in a more secure directory. The idea here is to
create a directory with 1733 permissions and use that for the save_path. For multi-php
a directory is created for each version of php so that each version can respect its own
session.gc_maxlifetime value. The sessions files are cleaned up every 30 minutes by a
cronjob.

=head3 Arguments

=over 4

=item $path

A scalar which contains the path we want to create for session storage. This will default
to the global value, $SESSION_SAVE_PATH.

=item $overwrite

Toggles if we want to overwrite the existing value in php.ini. Only used for when /tmp is
hardcoded in php.ini and we want to switch it to a different value during an upgrade.
This stops us from clobbering php.ini if the user wants to switch back to using /tmp.

=back

=head3 Returns

Nothing.  Completion implies valid input.

=head3 Dies

Any validation failure will result in a Cpanel::Exception.  Failure
cases include:

=over 4

=item *

The failure to create the specified path.

=back

=cut

sub setup_session_save_path {
    my ($args) = @_;

    $args->{'path'} ||= $SESSION_SAVE_PATH;

    create_sessions_dir( $args->{'path'}, 0711 );

    my $php      = Cpanel::ProgLang->new( type => 'php' );
    my $packages = $php->get_installed_packages();
  PACKAGE: foreach my $pack ( @{$packages} ) {

        create_sessions_dir( "$args->{'path'}/$pack", 01733 );
        my $ini        = $php->get_ini( 'package' => $pack );
        my $directives = $ini->get_basic_directives( 'all' => 1 );

        # Do nothing if files are not used for sessions.
        foreach my $directive ( @{$directives} ) {
            if ( $directive->{'key'} eq 'session.save_handler' && $directive->{'value'} ne 'files' ) {
                next PACKAGE;
            }
        }

        foreach my $directive ( @{$directives} ) {
            if ( $directive->{'key'} eq 'session.save_path' && ( !$directive->{'value'} || $directive->{'value'} eq 'NULL' || $args->{'overwrite'} ) ) {
                $ini->set_directives( 'directives' => { 'session.save_path' => "$args->{'path'}/$pack", 'session.gc_probability' => '0', 'session.gc_divisor' => '0' } );
                next PACKAGE;
            }
        }
    }
    return 1;

}

sub create_sessions_dir {
    my ( $path, $perm ) = @_;

    if ( !-e $path ) {
        Cpanel::SafeDir::MK::safemkdir($path) or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ 'path' => $path, 'error' => $! ] );
    }

    my $oldmask = umask(0);
    Cpanel::Autodie::chown( 0, 0, $path );
    Cpanel::Autodie::chmod( $perm, $path );
    umask($oldmask);

    return 1;

}

=head1 CONFIGURATION AND ENVIRONMENT

The module has no dependencies on environment variables.  It makes
changes to php.ini configuration files within system and user
directories, but has no configuration files which it needs to govern
its behaviour.

=head1 DEPENDENCIES

HTML::Entities, Cpanel::Exception,
Cpanel::Version::Compare, and Cwd.

=head1 TODO

The constructor could return undef, in the case of a not-installed
package name.  Moar validation!

=head1 SEE ALSO

L<Cpanel::ProgLang::Overview>, L<Cpanel::ProgLang::Supported::php>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2016, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;

__END__
