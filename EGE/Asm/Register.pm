# Copyright © 2013 Natalia D. Zemlyannikova
# Licensed under GPL version 2 or later.
# http://github.com/NZem/EGE
package EGE::Asm::Register;

use strict;
use warnings;

use EGE::Bits;
use EGE::Asm::Eflags;
use EGE::Random;


sub new {
    my ($class, %init) = @_;
    my $self = {
        id_from => undef,
        id_to => undef,
        bits => EGE::Bits->new->set_size(32),
        %init,
    };
    bless $self, ref $class || $class;
    $self;
}

my %reg_indexes = (
    (map { $_ . 'l' => [ 24, 32 ] } 'a'..'d'),
    (map { $_ . 'h' => [ 16, 24 ] } 'a'..'d'),
    (map { $_ . 'x' => [ 16, 32 ] } 'a'..'d'),
    (map { $_ => [ 0, 32 ] } 'ebp', 'esp', map "e${_}x", 'a'..'d'),
);

sub set_indexes {
    my ($self, $reg) = @_;
    ($self->{id_from}, $self->{id_to}) = @{$reg_indexes{$reg}};
    $self;
}

sub get_value {
    my ($self, $reg, $flip) = @_;
    $self->set_indexes($reg) if $reg;
    my $len = $self->{id_to} - $self->{id_from};
    my $tmp = EGE::Bits->new->
        set_bin_array([ @{$self->{bits}->{v}}[$self->{id_from} .. $self->{id_to} - 1] ], 1);
    $tmp->{v}[rnd->in_range(0, $len - 1)] ^= 1 if $flip;
    $tmp->get_dec();
}

sub set_ZSPF {
    my ($self, $eflags) = @_;
    $eflags->{ZF} = $self->get_value() ? 0 : 1;
    $eflags->{SF} = $self->{bits}->{v}[$self->{id_from}];
    $eflags->{PF} = 1 - scalar(grep $self->{bits}->{v}[$_], 24 .. 31) % 2;
    $self;
}

sub mov_value {
    my ($self, $val) = @_;
    my $len = $self->{id_to} - $self->{id_from};
    $val += 2 ** $len if $val < 0;
    my $tmp = EGE::Bits->new->set_size($len)->set_dec($val);
    splice @{$self->{bits}->{v}}, $self->{id_from}, $len, @{$tmp->{v}};
    $self;
}

sub mov {
    my ($self, $eflags, $reg, $val) = @_;
    $self->set_indexes($reg) if $reg;
    $self->mov_value($val);
}

sub movzx {
    my ($self, $eflags, $reg, $val) = @_;
    $val = 2**(($self->{id_to} - $self->{id_from})/2) + $val if ($val < 0);
    $self->mov($eflags, $reg, $val);
}

sub movsx {
    my ($self, $eflags, $reg, $val) = @_;
    $val = 2**(($self->{id_to} - $self->{id_from})/2) + $val if ($val < 0);
    $self->mov($eflags, $reg, $val);
    my $mid = ($self->{id_from} + $self->{id_to}) / 2;
    my $s = $self->{bits}->{v}[$mid];
    $self->{bits}->{v}[$_] = $s for ($self->{id_from} .. $mid-1);
    $self;
}

sub add {
    my ($self, $eflags, $reg, $val, $cf) = @_;
    $self->set_indexes($reg);
    my $a = 2**($self->{id_to} - $self->{id_from});
    $val = $a + $val if ($val < 0);
    my $regs = $self->{bits}->{v}[$self->{id_from}];
    my $vals = 0;
    $vals = 1 if ($val >= $a/2);
    my $newval = $self->get_value() + $val;
    $newval++ if ($cf && $eflags->{CF});
    $eflags->{CF} = 0;
    $eflags->{CF} = 1, $newval %= $a if ($newval >= $a);
    $self->mov($eflags, '', $newval);
    $eflags->{OF} = 0;
    my $ress = $self->{bits}->{v}[$self->{id_from}];
    $eflags->{OF} = 1 if ($regs == $vals && $regs != $ress);
    $self->set_ZSPF($eflags);
    $self;
}

sub adc {
    my ($self, $eflags, $reg, $val) = @_;
    $self->add($eflags, $reg, $val, 1);
}

sub dec {
    my ($self, $eflags, $reg) = @_;
    $self->sub($eflags, $reg, 1);
}

sub div {
    my ($self, $eflags, $reg, $val, $proc) = @_;
    my $eax = $proc->get_register('eax');
    my $size = $self->{id_to} - $self->{id_from};
    my ($first, $result, $result_mod) = (0, 0, 0);
    my $second = $self->get_value($reg);
    
    if($size == 8) {
        $first = $eax->get_value('ax');
        $result = int(abs($first / $second));
        $result_mod = abs($first) % abs($second);
        $eax->mov($eflags, 'al', $result);
        $eax->mov($eflags, 'ah', $result_mod);
    }
    $self;
}

sub idiv {
    my ($self, $eflags, $reg, $val, $proc) = @_;
    my $eax = $proc->get_register('eax');
    my $size_first = $eax->{id_to} - $eax->{id_from};
    my $size_second = $self->{id_to} - $self->{id_from};
    my ($first, $result) = (0, 0);
    my $second = $self->get_value($reg);
    
    if($size_second == 8) {
        my ($first_sign_flag, $second_sign_flag) 
         = ($eax->{bits}->{v}[$eax->{id_from}], $self->{bits}->{v}[$self->{id_from}]);
        my $first_sign  = $first_sign_flag  ? -1 : 1;
        my $second_sign = $second_sign_flag ? -1 : 1;
        
        $first = $eax->get_value('ax');
        $first = 2**$size_first - $first if $first_sign_flag && $first != 0;
        $second = 2**$size_second - $second if $second_sign_flag && $second != 0;
        $result = int( ($first_sign * $first) / ($second_sign * $second) );
        my $result_mod = $first_sign * ($first % $second);
        $eax->mov($eflags, 'al', $result);
        $eax->mov($eflags, 'ah', $result_mod);
    }
    $self;
}

sub inc {
    my ($self, $eflags, $reg) = @_;
    $self->add($eflags, $reg, 1);
}

sub imul {
    my ($self, $eflags, $reg, $val, $proc) = @_;
    my $eax = $proc->get_register('eax');
    my $size = $self->{id_to} - $self->{id_from};
    my ($first, $result) = (0, 0);
    my $second = $self->get_value($reg);
    
    if($size == 8) {
        my ($first_sign_flag, $second_sign_flag) 
         = ($eax->{bits}->{v}[$eax->{id_from}], $self->{bits}->{v}[$self->{id_from}]);
        my $first_sign  = $first_sign_flag  ? -1 : 1;
        my $second_sign = $second_sign_flag ? -1 : 1;
        
        $first = $eax->get_value('al');
        $first = 2**$size - $first if $first_sign_flag && $first != 0;
        $second = 2**$size - $second if $second_sign_flag && $second != 0;
        $result = $first_sign * $first * $second_sign * $second;
        $eax->mov($eflags, 'ax', $result);
    }
    $eflags->{CF} = 0;
    $eflags->{OF} = 0;
    $eflags->{CF} = 1, $eflags->{OF} = 1 if $result >= 2**($size);
    $self;
}

sub mul {
    my ($self, $eflags, $reg, $val, $proc) = @_;
    my $eax = $proc->get_register('eax');
    my $size = $self->{id_to} - $self->{id_from};
    my ($first, $result) = (0, 0);
    my $second = $self->get_value($reg);
    
    if($size == 8) {
        $first = $eax->get_value('al');
        $result = abs($first * $second);
        $eax->mov($eflags, 'ax', $result);
    }
    $eflags->{CF} = 0;
    $eflags->{OF} = 0;
    $eflags->{CF} = 1, $eflags->{OF} = 1 if $result >= 2**($size);
    $self;
}

sub sub {
    my ($self, $eflags, $reg, $val, $use_cf) = @_;
    $self->set_indexes($reg) if $reg;
    my $oldcf = $use_cf ? $eflags->{CF} : 0;
    my $a = 2 ** ($self->{id_to} - $self->{id_from});
    $val += $a if $val < 0;
    my $regval = $self->get_value();
    $eflags->{CF} = $regval < $val + $oldcf ? 1 : 0;
    $regval -= $a if $regval >= $a / 2;
    $val -= $a if $val >= $a / 2;
    my $newval = $regval - $val - $oldcf;
    $eflags->{OF} = $newval >= $a / 2 || $newval < -$a / 2 ? 1 : 0;
    $newval %= $a;
    $self->mov_value($newval)->set_ZSPF($eflags);
}

sub sbb {
    my ($self, $eflags, $reg, $val) = @_;
    $self->sub($eflags, $reg, $val, 1);
}

sub cmp {
    my ($self, $eflags, $reg, $val) = @_;
    my $tmp = $self->new;
    $tmp->{bits}->copy($self->{bits});
    $tmp->sub($eflags, $reg, $val);
}

sub neg {
    my ($self, $eflags, $reg) = @_;
    my $val = $self->get_value($reg);
    $self->mov($eflags, '', 0);
    $self->sub($eflags, '', $val);
    $self;
}

sub and {
    my ($self, $eflags, $reg, $val) = @_;
    $self->set_indexes($reg) if ($reg);
    $val = 2**($self->{id_to} - $self->{id_from}) + $val if ($val < 0);
    $self->{bits}->logic_op('and', $val, $self->{id_from}, $self->{id_to});
    $self->set_ZSPF($eflags);
    $eflags->{OF} = 0;
    $eflags->{CF} = 0;
    $self;
}

sub or {
    my ($self, $eflags, $reg, $val) = @_;
    $self->set_indexes($reg);
    $val = 2**($self->{id_to} - $self->{id_from}) + $val if ($val < 0);
    $self->{bits}->logic_op('or', $val, $self->{id_from}, $self->{id_to});
    $self->set_ZSPF($eflags);
    $eflags->{OF} = 0;
    $eflags->{CF} = 0;
    $self;
}

sub xor {
    my ($self, $eflags, $reg, $val) = @_;
    $self->set_indexes($reg);
    $val = 2**($self->{id_to} - $self->{id_from}) + $val if ($val < 0);
    $self->{bits}->logic_op('xor', $val, $self->{id_from}, $self->{id_to});
    $self->set_ZSPF($eflags);
    $eflags->{OF} = 0;
    $eflags->{CF} = 0;
    $self;
}

sub test {
    my ($self, $eflags, $reg, $val) = @_;
    my $oldval = $self->get_value($reg);
    $self->and($eflags, '', $val);
    $self->mov($eflags, '', $oldval);   
    $self;
}

sub not {
    my ($self, $eflags, $reg) = @_;
    $self->set_indexes($reg);
    $self->{bits}->logic_op('not', '', $self->{id_from}, $self->{id_to});
    $self;
}

sub shl {
    my ($self, $eflags, $reg, $val) = @_;
    $self->set_indexes($reg) if ($reg);
    my $v = $self->{bits}->{v};
    $eflags->{CF} = $v->[$self->{id_from}+$val-1];
    my $j = $self->{id_from};
    my $len = $self->{id_to} - $self->{id_from};
    $v->[$j++] = $val < $len ? $v->[$self->{id_from}+$val++] : 0 while $j < $self->{id_from} + $len;
    $self->set_ZSPF($eflags) if ($reg);
    $eflags->{OF} = 0 if ($reg);
    $self;
}

sub sal {
    my ($self, $eflags, $reg, $val) = @_;
    $self->set_indexes($reg);
    $eflags->{OF} = $self->{bits}->{v}[$self->{id_from}+$val-1] != $self->{bits}->{v}[$self->{id_from}+$val];
    $self->shl($eflags, '', $val);
    $self->set_ZSPF($eflags);
    $self;
}

sub shr {
    my ($self, $eflags, $reg, $val) = @_;
    $self->set_indexes($reg) if ($reg);
    my $v = $self->{bits}->{v};
    $eflags->{CF} = $v->[$self->{id_to}-$val];
    my $j = $self->{id_to};
    my $i = $self->{id_to} - $val;
    $v->[--$j] = $i ? $v->[--$i] : 0 while $j > $self->{id_from};
    $self->set_ZSPF($eflags) if ($reg);
    $eflags->{OF} = 0 if ($reg);
    $self;
}

sub sar {
    my ($self, $eflags, $reg, $val) = @_;
    $self->set_indexes($reg);
    my $sgn = $self->{bits}->{v}[$self->{id_from}];
    $self->shr($eflags, '', $val);
    $self->{bits}->{v}[$self->{id_from}+$_] = $sgn for (0..$val-1);
    $self->set_ZSPF($eflags);
    $eflags->{OF} = 0;
    $self;
}

sub rol {
    my ($self, $eflags, $reg, $val) = @_;
    $self->rotate_shift($eflags, $reg, $val, sub {
        $self->shl($eflags, '', 1);
        $self->{bits}->{v}[$self->{id_to} - 1] = $eflags->{CF};
    });
    $self;
}

sub rcl {
    my ($self, $eflags, $reg, $val) = @_;
    $self->rotate_shift($eflags, $reg, $val, sub {
        my $prevc = $eflags->{CF};
        $self->shl($eflags, '', 1);
        $self->{bits}->{v}[$self->{id_to} - 1] = $prevc;
    });
    $self;
}

sub ror {
    my ($self, $eflags, $reg, $val) = @_;
    $self->rotate_shift($eflags, $reg, $val, sub {
        $self->shr($eflags, '', 1);
        $self->{bits}->{v}[$self->{id_from}] = $eflags->{CF};
    });
    $self;
}

sub rcr {
    my ($self, $eflags, $reg, $val) = @_;
    $self->rotate_shift($eflags, $reg, $val, sub {
        my $prevc = $eflags->{CF};
        $self->shr($eflags, '', 1);
        $self->{bits}->{v}[$self->{id_from}] = $prevc;
    });
    $self;
}

sub rotate_shift {
    my ($self, $eflags, $reg, $val, $sub) = @_;
    $self->set_indexes($reg);
    $val %= $self->{id_to} - $self->{id_from};
    for (1..$val) {
        $sub->();
    }
    $self->set_ZSPF($eflags);
    $eflags->{OF} = 0;
    $self;
}

sub push {
    my ($self, $eflags, $reg, $stack) = @_;
    unshift @{$stack}, $self->get_value($reg);
    $self;
}

sub pop {
    my ($self, $eflags, $reg, $stack) = @_;
    $self->mov($eflags, $reg, shift @{$stack});
    $self;
}

1;
