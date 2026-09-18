import 'package:flutter/material.dart';

import 'material_request_panel_base.dart' as buying;

class MaterialRequestPanel extends StatelessWidget {
  final bool canCreateMaterialRequest;
  final bool canCreatePurchaseOrder;

  const MaterialRequestPanel({
    super.key,
    this.canCreateMaterialRequest = true,
    this.canCreatePurchaseOrder = true,
  });

  @override
  Widget build(BuildContext context) => buying.MaterialRequestPanel(
    canCreateMaterialRequest: canCreateMaterialRequest,
    canCreatePurchaseOrder: canCreatePurchaseOrder,
  );
}
