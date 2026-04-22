const fs = require('fs');
const path = 'c:/Users/ADMIN/Desktop/Krishnaswamy Institution/KCET/KCET/lib/screens/fees/student_fee_collection_screen.dart';
let content = fs.readFileSync(path, 'utf8');

// Target only outer cards: `color: Colors.white,\n...borderRadius: BorderRadius.circular(12.r),\n...border: Border.all(color: AppColors.border)`
const cardRadiusPatterns = [
  // Outer cards (color: Colors.white + radius 12.r + AppColors.border)
  [
    `color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.border),`,
    `color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),`,
  ],
  [
    `color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.border),`,
    `color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),`,
  ],
  [
    `color: Colors.white,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColors.border),`,
    `color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),`,
  ],
  [
    `color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),`,
    `color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),`,
  ],
];

let total = 0;
for (const [old, newStr] of cardRadiusPatterns) {
  const c = content.split(old).length - 1;
  if (c > 0) {
    console.log(`  ${c}×`);
    content = content.split(old).join(newStr);
    total += c;
  }
}

fs.writeFileSync(path, content, 'utf8');
console.log(`Total outer cards updated: ${total}`);
