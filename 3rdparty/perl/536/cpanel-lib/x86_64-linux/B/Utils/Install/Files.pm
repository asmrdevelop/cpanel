package B::Utils::Install::Files;

$self = {
          'deps' => [],
          'inc' => '',
          'libs' => '',
          'typemaps' => [
                          'typemap'
                        ]
        };

@deps = @{ $self->{deps} };
@typemaps = @{ $self->{typemaps} };
$libs = $self->{libs};
$inc = $self->{inc};

	$CORE = undef;
	foreach (@INC) {
		if ( -f $_ . "/B/Utils/Install/Files.pm") {
			$CORE = $_ . "/B/Utils/Install/";
			last;
		}
	}

	sub deps { @{ $self->{deps} }; }

	sub Inline {
		my ($class, $lang) = @_;
		+{ map { (uc($_) => $self->{$_}) } qw(inc libs typemaps) };
	}

1;
