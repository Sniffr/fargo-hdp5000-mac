0005d906 <_nCalculateResidualEnergy>: 
5d906:      %ebp 
5d907:      %esp, %ebp 
5d909:      %esi 
5d90a:      $0x24, %esp 
5d90d:      0x14(%ebp), %eax 
5d910:      (%eax,%eax), %edx 
5d913:      0xc(%ebp), %eax 
5d916:      0x8(%ebp), %eax 
5d919:      %eax, %edx 
5d91b:      0x5d925 <_nCalculateResidualEnergy+0x1f> 
5d91d:      0x24(%ebp), %eax 
5d920:      %eax, -0xc(%ebp) 
5d923:      0x5d92b <_nCalculateResidualEnergy+0x25> 
5d925:      0x30(%ebp), %eax 
5d928:      %eax, -0xc(%ebp) 
5d92b:      0x14(%ebp), %edx 
5d92e:      0x8(%ebp), %eax 
5d931:      %eax, %ecx 
5d933:      %edx, %ecx 
5d935:      0x14(%ebp), %edx 
5d938:      0xc(%ebp), %eax 
5d93b:      %edx, %eax 
5d93d:      (%ecx,%eax), %eax 
5d940:      %eax, %esi 
5d942:      -0xc(%ebp), %esi 
5d946:      0x14(%ebp), %edx 
5d949:      0x10(%ebp), %eax 
5d94c:      %eax, %ecx 
5d94e:      %edx, %ecx 
5d950:      0x14(%ebp), %edx 
5d953:      0x18(%ebp), %eax 
5d956:      %edx, %eax 
5d958:      (%ecx,%eax), %eax 
5d95b:      0x28(%ebp), %eax 
5d95f:      %eax, %esi 
5d961:      0x14(%ebp), %edx 
5d964:      0x1c(%ebp), %eax 
5d967:      %eax, %ecx 
5d969:      %edx, %ecx 
5d96b:      0x14(%ebp), %edx 
5d96e:      0x20(%ebp), %eax 
5d971:      %edx, %eax 
5d973:      (%ecx,%eax), %eax 
5d976:      0x2c(%ebp), %eax 
5d97a:      (%esi,%eax), %eax 
5d97d:      0xbb8(%eax), %ecx 
5d983:      $0x57619f1, -0x1c(%ebp) ## imm = 0x57619F1 
5d98a:      -0x1c(%ebp), %eax 
5d98d:      %ecx 
5d98f:      $0x7, %edx 
5d992:      %ecx, %eax 
5d994:      $0x1f, %eax 
5d997:      %edx, %ecx 
5d999:      %eax, %ecx 
5d99b:      %ecx, %eax 
5d99d:      0x14(%ebp), %eax 
5d9a0:      %eax, -0x10(%ebp) 
5d9a3:      $0xffff, -0x10(%ebp)    ## imm = 0xFFFF 
5d9aa:      0x5d9b3 <_nCalculateResidualEnergy+0xad> 
5d9ac:      $0xffff, -0x10(%ebp)    ## imm = 0xFFFF 
5d9b3:      -0x10(%ebp), %eax 
5d9b6:      $0x24, %esp 
5d9b9:      %esi 
5d9ba:      %ebp 
5d9bb:      $0x2c 
 
0005db33 <_nUpdateEnergy>: 
5db33:      %ebp 
5db34:      %esp, %ebp 
5db36:      %edi 
5db37:      %esi 
5db38:      $0x60, %esp 
5db3b:      0x8(%ebp), %eax 
5db3e:      $0xc38, %eax            ## imm = 0xC38 
5db43:      %eax, -0x10(%ebp) 
5db46:      0x10(%ebp), %eax 
5db49:      %al, %edx 
5db4c:      %edx, %eax 
5db4e:      $0x2, %eax 
5db51:      %edx, %eax 
5db53:      $0xa, %eax 
5db56:      0x32000(%eax), %ecx 
5db5c:      $0x2e8ba2e9, -0x2c(%ebp) ## imm = 0x2E8BA2E9 
5db63:      -0x2c(%ebp), %eax 
5db66:      %ecx 
5db68:      $0x2, %edx 
5db6b:      %ecx, %eax 
5db6d:      $0x1f, %eax 
5db70:      %eax, %edx 
5db72:      0x8(%ebp), %eax 
5db75:      $0x8, %eax 
5db78:      (%eax), %eax 
5db7a:      $0xffff, %eax           ## imm = 0xFFFF 
5db7f:      %eax, %edx 
5db81:      %edx, %eax 
5db83:      $0x1f, %eax 
5db86:      %edx, %eax 
5db88:      %eax 
5db8a:      %eax, -0xc(%ebp) 
5db8d:      0xc(%ebp), %esi 
5db90:      $0x4, %esi 
5db93:      -0x10(%ebp), %eax 
5db96:      $0x4, %eax 
5db99:      (%eax), %edx 
5db9b:      -0x10(%ebp), %eax 
5db9e:      (%eax), %eax 
5dba0:      $0x64, 0x28(%esp) 
5dba8:      $0xaa, 0x24(%esp) 
5dbb0:      $0x3e8, 0x20(%esp)      ## imm = 0x3E8 
5dbb8:      $0x64, 0x1c(%esp) 
5dbc0:      %edx, 0x18(%esp) 
5dbc4:      %eax, 0x14(%esp) 
5dbc8:      -0xc(%ebp), %eax 
5dbcb:      %eax, 0x10(%esp) 
5dbcf:      0x18(%ebp), %eax 
5dbd2:      %eax, 0xc(%esp) 
5dbd6:      0x14(%ebp), %eax 
5dbd9:      %eax, 0x8(%esp) 
5dbdd:      $0x64, 0x4(%esp) 
5dbe5:      $0x64, (%esp) 
5dbec:      0x5d906 <_nCalculateResidualEnergy> <_nCalculateResidualEnergy> 
5dbf1:      $0x2c, %esp 
5dbf4:      %eax, (%esi) 
5dbf6:      0xc(%ebp), %esi 
5dbf9:      $0xc, %esi 
5dbfc:      -0x10(%ebp), %eax 
5dbff:      $0x8, %eax 
5dc02:      (%eax), %ecx 
5dc04:      $0x88888889, -0x2c(%ebp) ## imm = 0x88888889 
5dc0b:      -0x2c(%ebp), %eax 
5dc0e:      %ecx 
5dc10:      (%edx,%ecx), %eax 
5dc13:      %eax, %edx 
5dc15:      $0x4, %edx 
5dc18:      %ecx, %eax 
5dc1a:      $0x1f, %eax 
5dc1d:      %edx, %edi 
5dc1f:      %eax, %edi 
5dc21:      -0x10(%ebp), %eax 
5dc24:      (%eax), %ecx 
5dc26:      $0x88888889, -0x2c(%ebp) ## imm = 0x88888889 
5dc2d:      -0x2c(%ebp), %eax 
5dc30:      %ecx 
5dc32:      (%edx,%ecx), %eax 
5dc35:      %eax, %edx 
5dc37:      $0x4, %edx 
5dc3a:      %ecx, %eax 
5dc3c:      $0x1f, %eax 
5dc3f:      %edx, %ecx 
5dc41:      %eax, %ecx 
5dc43:      -0x10(%ebp), %eax 
5dc46:      $0x8, %eax 
5dc49:      (%eax), %eax 
5dc4b:      %eax, -0x1c(%ebp) 
5dc4e:      -0x10(%ebp), %eax 
5dc51:      $0x4, %eax 
5dc54:      (%eax), %edx 
5dc56:      -0x10(%ebp), %eax 
5dc59:      (%eax), %eax 
5dc5b:      $0x32, 0x28(%esp) 
5dc63:      $0x1, 0x24(%esp) 
5dc6b:      $0x3e8, 0x20(%esp)      ## imm = 0x3E8 
5dc73:      $0x32, 0x1c(%esp) 
5dc7b:      %edi, 0x18(%esp) 
5dc7f:      %ecx, 0x14(%esp) 
5dc83:      -0x1c(%ebp), %ecx 
5dc86:      %ecx, 0x10(%esp) 
5dc8a:      %edx, 0xc(%esp) 
5dc8e:      %eax, 0x8(%esp) 
5dc92:      0x18(%ebp), %eax 
5dc95:      %eax, 0x4(%esp) 
5dc99:      0x14(%ebp), %eax 
5dc9c:      %eax, (%esp) 
5dc9f:      0x5d906 <_nCalculateResidualEnergy> <_nCalculateResidualEnergy> 
5dca4:      $0x2c, %esp 
5dca7:      %eax, (%esi) 
5dca9:      0xc(%ebp), %eax 
5dcac:      (%eax), %edx 
5dcae:      0x8(%ebp), %eax 
5dcb1:      %edx, (%eax) 
5dcb3:      0xc(%ebp), %eax 
5dcb6:      $0x8, %eax 
5dcb9:      (%eax), %edx 
5dcbb:      -0x10(%ebp), %eax 
5dcbe:      %edx, (%eax) 
5dcc0:      0xc(%ebp), %eax 
5dcc3:      $0x4, %eax 
5dcc6:      (%eax), %edx 
5dcc8:      0xc(%ebp), %eax 
5dccb:      %edx, (%eax) 
5dccd:      0xc(%ebp), %edx 
5dcd0:      $0x8, %edx 
5dcd3:      0xc(%ebp), %eax 
5dcd6:      $0xc, %eax 
5dcd9:      (%eax), %eax 
5dcdb:      %eax, (%edx) 
5dcdd:      -0xc(%ebp), %eax 
5dce0:      -0x8(%ebp), %esp 
5dce3:      %esi 
5dce4:      %edi 
5dce5:      %ebp 
5dce6:      $0x14 
 
0005d9be <_uAdjustBurnLevel>: 
5d9be:      %ebp 
5d9bf:      %esp, %ebp 
5d9c1:      %esi 
5d9c2:      $0x54, %esp 
5d9c5:      0xc(%ebp), %eax 
5d9c8:      $0xc38, %eax            ## imm = 0xC38 
5d9cd:      %eax, -0xc(%ebp) 
5d9d0:      -0xc(%ebp), %eax 
5d9d3:      $0x8, %eax 
5d9d6:      (%eax), %eax 
5d9d8:      %eax, -0x2c(%ebp) 
5d9db:      -0xc(%ebp), %eax 
5d9de:      $0xc, %eax 
5d9e1:      (%eax), %eax 
5d9e3:      %eax, -0x28(%ebp) 
5d9e6:      0xc(%ebp), %eax 
5d9e9:      $0x4, %eax 
5d9ec:      (%eax), %eax 
5d9ee:      %eax, -0x24(%ebp) 
5d9f1:      0xc(%ebp), %eax 
5d9f4:      $0x8, %eax 
5d9f7:      (%eax), %eax 
5d9f9:      %eax, -0x20(%ebp) 
5d9fc:      0xc(%ebp), %eax 
5d9ff:      $0xc, %eax 
5da02:      (%eax), %eax 
5da04:      %eax, -0x1c(%ebp) 
5da07:      0x8(%ebp), %eax 
5da0a:      %al, %edx 
5da0d:      %edx, %eax 
5da0f:      %eax, %eax 
5da11:      %edx, %eax 
5da13:      $0x5, %eax 
5da16:      %edx, %eax 
5da18:      $0x2, %eax 
5da1b:      %eax, -0x3c(%ebp) 
5da1e:      -0x20(%ebp), %edx 
5da21:      -0x2c(%ebp), %eax 
5da24:      %eax, %ecx 
5da26:      %edx, %ecx 
5da28:      -0x20(%ebp), %edx 
5da2b:      -0x28(%ebp), %eax 
5da2e:      %edx, %eax 
5da30:      (%ecx,%eax), %edx 
5da33:      %edx, %eax 
5da35:      $0x2, %eax 
5da38:      %edx, %eax 
5da3a:      %eax, %edx 
5da3c:      $0x4, %edx 
5da3f:      %edx, %eax 
5da41:      %eax, %eax 
5da43:      %eax, %ecx 
5da45:      -0x20(%ebp), %edx 
5da48:      -0x24(%ebp), %eax 
5da4b:      %eax, %esi 
5da4d:      %edx, %esi 
5da4f:      %esi, %edx 
5da51:      %edx, %eax 
5da53:      $0x2, %eax 
5da56:      %edx, %eax 
5da58:      (,%eax,4), %edx 
5da5f:      %edx, %eax 
5da61:      (,%eax,4), %edx 
5da68:      %edx, %eax 
5da6a:      $0x3, %eax 
5da6d:      %eax, %ecx 
5da6f:      -0x20(%ebp), %edx 
5da72:      -0x1c(%ebp), %eax 
5da75:      %eax, %esi 
5da77:      %edx, %esi 
5da79:      %esi, %edx 
5da7b:      %edx, %eax 
5da7d:      $0x2, %eax 
5da80:      %edx, %eax 
5da82:      (,%eax,4), %edx 
5da89:      %edx, %eax 
5da8b:      (,%eax,4), %edx 
5da92:      %edx, %eax 
5da94:      $0x3, %eax 
5da97:      (%ecx,%eax), %eax 
5da9a:      %eax, -0x40(%ebp) 
5da9d:      $0x0, -0x40(%ebp) 
5daa1:      0x5daaa <_uAdjustBurnLevel+0xec> 
5daa3:      $0xfff, -0x40(%ebp)     ## imm = 0xFFF 
5daaa:      -0x40(%ebp), %eax 
5daad:      $0xc, %eax 
5dab0:      -0x20(%ebp), %eax 
5dab3:      -0x3c(%ebp), %edx 
5dab6:      %eax, %edx 
5dab8:      %edx, %eax 
5daba:      $0x2, %eax 
5dabd:      %edx, %eax 
5dabf:      %eax, %eax 
5dac1:      %edx, %eax 
5dac3:      %eax, %eax 
5dac5:      0x70418(%eax), %ecx 
5dacb:      $0x66666667, -0x4c(%ebp) ## imm = 0x66666667 
5dad2:      -0x4c(%ebp), %eax 
5dad5:      %ecx 
5dad7:      $0xb, %edx 
5dada:      %ecx, %eax 
5dadc:      $0x1f, %eax 
5dadf:      %edx, %ecx 
5dae1:      %eax, %ecx 
5dae3:      %ecx, %eax 
5dae5:      $0x28, %eax 
5dae8:       
5dae9:      %eax, -0x18(%ebp) 
5daec:      %edx, -0x14(%ebp) 
5daef:      $0x0, -0x14(%ebp) 
5daf3:      0x5db05 <_uAdjustBurnLevel+0x147> 
5daf5:      $0x0, -0x18(%ebp) 
5dafc:      $0x0, -0x14(%ebp) 
5db03:      0x5db28 <_uAdjustBurnLevel+0x16a> 
5db05:      $0x0, -0x14(%ebp) 
5db09:      0x5db28 <_uAdjustBurnLevel+0x16a> 
5db0b:      $0x0, -0x14(%ebp) 
5db0f:      0x5db1a <_uAdjustBurnLevel+0x15c> 
5db11:      $0xff, -0x18(%ebp) 
5db18:      0x5db28 <_uAdjustBurnLevel+0x16a> 
5db1a:      $0xff, -0x18(%ebp) 
5db21:      $0x0, -0x14(%ebp) 
5db28:      -0x18(%ebp), %eax 
5db2b:      $0x54, %esp 
5db2e:      %esi 
5db2f:      %ebp 
5db30:      $0x8 
 
0005dce9 <_nCalcResinLevel>: 
5dce9:      %ebp 
5dcea:      %esp, %ebp 
5dcec:      %ebx 
5dced:      $0x14, %esp 
5dcf0:      0x7f688 <___i686.get_pc_thunk.bx> <___i686.get_pc_thunk.bx> 
5dcf5:      0x8(%ebp), %eax 
5dcf8:      $0x1, %eax 
5dcfb:      (%eax), %eax 
5dcfe:      %al, %eax 
5dd01:      $0x1, %eax 
5dd04:      %al, %al 
5dd06:      0x5dd6a <_nCalcResinLevel+0x81> 
5dd08:      0x8(%ebp), %eax 
5dd0b:      $0x1, %eax 
5dd0e:      (%eax), %eax 
5dd11:      %al, %eax 
5dd14:      %eax, %edx 
5dd16:      $0x7, %edx 
5dd19:      0x2fe8b(%ebx), %eax 
5dd1f:      (%eax,%edx,4), %ecx 
5dd22:      0x8(%ebp), %eax 
5dd25:      (%eax), %eax 
5dd28:      %al, %eax 
5dd2b:      $0x3, %eax 
5dd2e:      0x4(%eax), %edx 
5dd31:      0x2fe6b(%ebx), %eax 
5dd37:      (%eax,%edx,4), %eax 
5dd3a:      %eax, %ecx 
5dd3c:      0x8(%ebp), %eax 
5dd3f:      $0x2, %eax 
5dd42:      (%eax), %eax 
5dd45:      %al, %eax 
5dd48:      $0x3, %eax 
5dd4b:      0x4(%eax), %edx 
5dd4e:      0x2fe6b(%ebx), %eax 
5dd54:      (%eax,%edx,4), %eax 
5dd57:      %ecx, %edx 
5dd59:      %eax, %edx 
5dd5b:      %edx, %eax 
5dd5d:      $0xb4, %eax 
5dd62:      %eax, -0xc(%ebp) 
5dd65:      0x5ddf7 <_nCalcResinLevel+0x10e> 
5dd6a:      0x8(%ebp), %eax 
5dd6d:      $0x2, %eax 
5dd70:      (%eax), %eax 
5dd73:      %al, %eax 
5dd76:      %eax, %edx 
5dd78:      $0x3, %edx 
5dd7b:      0x2fe6b(%ebx), %eax 
5dd81:      (%eax,%edx,4), %eax 
5dd84:      %eax, -0x18(%ebp) 
5dd87:      0x8(%ebp), %eax 
5dd8a:      $0x1, %eax 
5dd8d:      (%eax), %eax 
5dd90:      %al, %eax 
5dd93:      %eax, %edx 
5dd95:      $0x7, %edx 
5dd98:      0x2fe8b(%ebx), %eax 
5dd9e:      (%eax,%edx,4), %eax 
5dda1:      %eax, -0x10(%ebp) 
5dda4:      0x8(%ebp), %eax 
5dda7:      (%eax), %eax 
5ddaa:      %al, %eax 
5ddad:      %eax, %edx 
5ddaf:      $0x3, %edx 
5ddb2:      0x2fe6b(%ebx), %eax 
5ddb8:      (%eax,%edx,4), %eax 
5ddbb:      %eax, -0x14(%ebp) 
5ddbe:      -0x18(%ebp), %eax 
5ddc1:      -0x14(%ebp), %eax 
5ddc4:      0x5ddce <_nCalcResinLevel+0xe5> 
5ddc6:      -0x18(%ebp), %eax 
5ddc9:      %eax, -0xc(%ebp) 
5ddcc:      0x5ddd4 <_nCalcResinLevel+0xeb> 
5ddce:      -0x14(%ebp), %eax 
5ddd1:      %eax, -0xc(%ebp) 
5ddd4:      -0x10(%ebp), %eax 
5ddd7:      -0xc(%ebp), %eax 
5ddda:      0x5ddf1 <_nCalcResinLevel+0x108> 
5dddc:      0x8(%ebp), %eax 
5dddf:      $0x1, %eax 
5dde2:      (%eax), %eax 
5dde5:      %al, %eax 
5dde8:      %eax 
5ddea:      $0x1, %eax 
5dded:      %al, %al 
5ddef:      0x5ddf7 <_nCalcResinLevel+0x10e> 
5ddf1:      -0x10(%ebp), %eax 
5ddf4:      %eax, -0xc(%ebp) 
5ddf7:      -0xc(%ebp), %eax 
5ddfa:      $0x14, %esp 
5ddfd:      %ebx 
5ddfe:      %ebp 
5ddff:      $0x4 
 
