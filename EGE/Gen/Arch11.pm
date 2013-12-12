# Copyright © 2013 Alexey Krylov
# Licensed under GPL version 2 or later.
# http://github.com/forsaken1/EGE
package EGE::Gen::Arch11;
use base 'EGE::GenBase::SingleChoice';

use strict;
use warnings;
use utf8;

use EGE::Random;
use EGE::Asm::Processor;
use EGE::Asm::AsmCodeGenerate;

sub offs_modulo {
    my ($val, @offs) = @_;
    map { ($val + $_) } @offs;
}

sub make_wrongs {
    my ($reg, $upto, @variants) = @_;
    my @wrongs;
    for (my $i = 0; @variants + @wrongs < $upto && $i < 100; ++$i) {
        my $res = proc->get_wrong_val($reg);
        push @wrongs, $res unless grep { $res eq $_ } @variants, @wrongs;
    }
    @wrongs;
}

sub reg_value_mul_imul {
	my $self = shift;
	my ($reg, $format) = $self->generate_simple_code('mul');
	my @variants = $self->get_res($reg, $format, 'mul');
	
	push @variants, offs_modulo(@variants);
    $self->formated_variants($format, @variants, make_wrongs($reg, 4, @variants));
}

sub reg_value_div_idiv {
	my $self = shift;
	my ($reg, $format) = $self->generate_simple_code('div');
	my @variants = $self->get_res($reg, $format, 'div');
	
    $self->formated_variants($format, @variants, make_wrongs($reg, 4, @variants));
}

sub generate_simple_code {
	my ($self, $type) = @_;
	my $format = '%s';
	my @reg = $self->get_reg($type);
	
	cgen->{code} = [];
	
	$self->generate_mov_commands($type, @reg);
	$self->generate_single_command($type, $reg[1]);
	
	($reg[1], $format);
}

sub generate_mov_commands {
	my ($self, $type, $reg1, $reg2) = @_;
	my ($arg1, $arg2);
	
	if ($type eq 'mul') {
		$arg1 = rnd->pick(rnd->in_range(5, 10), rnd->in_range(-10, -5));
		$arg2 = rnd->pick(rnd->in_range(5, 10), rnd->in_range(-10, -5));
		$arg1 = -$arg1 if $arg1 * $arg2 > 0;
	}
	elsif($type eq 'div') {
		$arg1 = rnd->in_range(50, 127);
		$arg2 = rnd->pick(rnd->in_range(5, 10), rnd->in_range(-10, -5));
	}
	cgen->add_command('mov', $reg1, $arg1);
	cgen->add_command('mov', $reg2, $arg2);
}

sub generate_single_command {
	my ($self, $type, $reg) = @_;
	my $cmd;
	
	if ($type eq 'mul') {
		$cmd = rnd->pick('mul', 'imul');
	}
	elsif($type eq 'div') {
		$cmd = rnd->pick('div', 'idiv');
	}
	cgen->add_command($cmd, $reg);
}

sub get_reg {
	my ($self, $type) = @_;
	
	if ($type eq 'mul') {
		('al', 'bl');
	}
	elsif ($type eq 'div') {
		('ax', 'bl');
	}
}

sub get_res {
    my ($self, $reg, $format, $type) = @_;
    my $code_txt = cgen->get_code_txt($format);
	my $register = $self->get_result_register($type);
	
    $self->{text} = "В результате выполнения кода $code_txt в регистре $register будет содержаться значение:";
    my $run = proc->run_code(cgen->{code});
	
	if($type =~ /mul/) {
		cgen->{code}->[2]->[0] = cgen->{code}->[2]->[0] eq 'mul' ? 'imul' : 'mul';
		(
			$run->get_val($register), 
			proc->run_code(cgen->{code})->get_val($register)
		);
	} else {
		my $another_reg = $register eq 'ah' ? 'al' : 'ah';
		cgen->{code}->[2]->[0] = cgen->{code}->[2]->[0] eq 'div' ? 'idiv' : 'div';
		(
			$run->get_val($register),
			$run->get_val($another_reg),
		);
	}
}

sub get_result_register {
	my ($self, $type) = @_;
	
	if ($type =~ /mul/) {
		'ax';
	}
	elsif($type =~ /div/) {
		rnd->pick('ah', 'al');
	}
}

1;