// dateGeneratorHandler.js
export const handler = async (event) => {
    const { startDate, endDate, generateType } = event;

    if (!startDate || !endDate) {
        throw new Error("Event must contain 'startDate' and 'endDate' properties.");
    }

    const start = new Date(startDate);
    const end = new Date(endDate);
    const dateList = [];

    if (generateType === 'daily') {
        let current = new Date(start);
        while (current < end) {
            const nextDay = new Date(current);
            nextDay.setDate(current.getDate() + 1);
            dateList.push({
                startDate: current.toISOString(),
                endDate: nextDay.toISOString()
            });
            current = nextDay;
        }
        console.log(`Generated ${dateList.length} daily chunks from ${startDate} to ${endDate}`);
    } else { // Default to monthly chunks
        let current = new Date(start);
        while (current < end) {
            const nextMonth = new Date(current);
            nextMonth.setMonth(current.getMonth() + 1);
            if (nextMonth > end) {
                dateList.push({
                    startDate: current.toISOString(),
                    endDate: end.toISOString()
                });
                break;
            }
            dateList.push({
                startDate: current.toISOString(),
                endDate: nextMonth.toISOString()
            });
            current = nextMonth;
        }
        console.log(`Generated ${dateList.length} monthly chunks from ${startDate} to ${endDate}`);
    }

    return dateList;
};